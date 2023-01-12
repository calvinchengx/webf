import fs from 'fs';
import path from 'path';
import {DAPInfoCollector, ParameterType} from "../analyzer";
import _ from "lodash";
import {addIndent} from "../idl/utils";
import {ClassObject, FunctionArgumentType, PropsDeclaration} from "../idl/declaration";

function readConverterTemplate() {
  return fs.readFileSync(path.join(__dirname, '../../../templates/dap_templates/dap_converter.c.tpl'), {encoding: 'utf-8'});
}

function getLists(set: Set<ClassObject>): string[] {
  return Array.from(set).map(s => {
    return s.name;
  });
}

const stringifyTypes = {};
const getTypes = {};

function generateTypeStringify(object: ClassObject, propName: string, info: DAPInfoCollector, externalInitialize: string[]): void {
  if (stringifyTypes[object.name]) return;

  stringifyTypes[object.name] = true;

  let stringifyCode : string[] = [];
  if (object.props) {
    object.props.forEach(prop => {
      let code = generateMemberStringifyCode(prop, propName, externalInitialize, info);
      if (code) {
        stringifyCode.push(`{\n ${code} \n }`);
      }
    });
  }

  externalInitialize.push(`static JSValue stringify_property_${object.name}(JSContext* ctx, ${object.name}* ${propName}) {
  JSValue object = JS_NewObject(ctx);
  ${stringifyCode.join('\n')}
  return object;
  }`)
}

function generateTypeInitialize(object: ClassObject, propTypeName: ParameterType, info: DAPInfoCollector, externalInitialize: string[]): void {
  if (getTypes[object.name]) return;
  getTypes[object.name] = true;
  let parserCode: string[] = [];
  if (object.props) {
    object.props.forEach(prop => {
      let code = generatePropParser(prop, externalInitialize, info);
      if (code) {
        parserCode.push(code);
      }
    });
  }

  externalInitialize.push(`static ${object.name}* get_property_${propTypeName.value}(JSContext* ctx, JSValue this_object, const char* prop) {
  JSValue arguments = JS_GetPropertyStr(ctx, this_object, prop);
  ${object.name}* args = js_malloc(ctx, sizeof(${object.name}));
  ${parserCode.join('\n')}
  JS_FreeValue(ctx, arguments);
  return args;
}`);
}

function generatePropParser(prop: PropsDeclaration, externalInitialize: string[], info: DAPInfoCollector): string | null {
  function wrapOptional(code: string) {
    function generateUnInitializeValue(): string {
      if (prop.type.value === FunctionArgumentType.dom_string) {
        callCode = `args->${prop.name} = NULL;`;
      } else if (prop.type.value === FunctionArgumentType.double) {
        callCode = `args->${prop.name} = 0.0;`;
      } else if (prop.type.value === FunctionArgumentType.int64) {
        callCode = `args->${prop.name} = 0;`
      } else if (prop.type.value === FunctionArgumentType.boolean) {
        callCode = `args->${prop.name} = 0;`
      } else {
        callCode = `args->${prop.name} = NULL;`;
      }
      return callCode;
    }

    return addIndent(`if (JS_HasPropertyStr(ctx, arguments, "${prop.name}")) {
  ${code}    
} else {
  ${generateUnInitializeValue()}
}`, 2);
  }

  let callCode = '';
  if (prop.type.value === FunctionArgumentType.dom_string) {
    callCode = `args->${prop.name} = get_property_string_copy(ctx, arguments, "${prop.name}");`;
  } else if (prop.type.value === FunctionArgumentType.double) {
    callCode = `args->${prop.name} = get_property_float64(ctx, arguments, "${prop.name}");`;
  } else if (prop.type.value === FunctionArgumentType.int64) {
    callCode = `args->${prop.name} = get_property_int64(ctx, arguments, "${prop.name}");`
  } else if (prop.type.value === FunctionArgumentType.boolean) {
    callCode = `args->${prop.name} = get_property_boolean(ctx, arguments, "${prop.name}");`
  } else {
    let targetTypes = Array.from(info.others).find(o => o.name === prop.type.value);

    if (targetTypes) {
      generateTypeInitialize(targetTypes, prop.type, info, externalInitialize);
      callCode = `args->${prop.name} = get_property_${prop.type.value}(ctx, arguments, "${prop.name}");`
    }
  }

  return prop.optional ? wrapOptional(callCode) : callCode;
}

function generateMemberInit(prop: PropsDeclaration, externalInitialize: string[], info: DAPInfoCollector): string {
  let initCode = '';
  if (prop.type.value === FunctionArgumentType.boolean) {
    initCode = `body->${prop.name} = 0;`;
  } else if (prop.type.value === FunctionArgumentType.int64 || prop.type.value === FunctionArgumentType.double) {
    initCode = `body->${prop.name} = 0;`;
  } else {
    initCode = `body->${prop.name} = NULL;`;
  }
  return initCode;
}

function generateMemberStringifyCode(prop: PropsDeclaration, bodyName: string, externalInitialize: string[], info: DAPInfoCollector): string {
  function wrapIf(code: string) {
    if (prop.type.value === FunctionArgumentType.dom_string || typeof prop.type.value === 'string') {
      return `if (${bodyName}->${prop.name} != NULL) {
  ${code}
}`;
    }
    return code;
  }

  function generateQuickJSInitFromType(type: ParameterType) {
    if (type.value === FunctionArgumentType.double) {
      return `JS_NewFloat64`;
    } else if (type.value === FunctionArgumentType.dom_string) {
      return `JS_NewString`;
    } else if (type.value === FunctionArgumentType.int64) {
      return `JS_NewInt64`;
    } else if (type.value === FunctionArgumentType.boolean) {
      return `JS_NewBool`;
    } else {
      let targetTypes = Array.from(info.others).find(o => o.name === type.value);
      if (targetTypes) {
        generateTypeStringify(targetTypes, prop.name, info, externalInitialize);
        return `stringify_property_${targetTypes.name}`;
      }
    }
    return '';
  }

  function genCallCode(type: ParameterType, prop: PropsDeclaration) {
    let callCode = '';
    if (type.value === FunctionArgumentType.int64) {
      callCode = `JS_SetPropertyStr(ctx, object, "${prop.name}", ${generateQuickJSInitFromType(type)}(ctx, ${bodyName}->${prop.name}));`;
    } else if (type.value === FunctionArgumentType.boolean) {
      callCode = `JS_SetPropertyStr(ctx, object, "${prop.name}", ${generateQuickJSInitFromType(type)}(ctx, ${bodyName}->${prop.name}));`;
    } else if (type.value === FunctionArgumentType.dom_string) {
      callCode = `JS_SetPropertyStr(ctx, object, "${prop.name}", ${generateQuickJSInitFromType(type)}(ctx, ${bodyName}->${prop.name}));`;
    } else if (type.value === FunctionArgumentType.double) {
      callCode = `JS_SetPropertyStr(ctx, object, "${prop.name}", ${generateQuickJSInitFromType(type)}(ctx, ${bodyName}->${prop.name}));`;
    } else {
      if (type.isArray) {
        let isReference = typeof (prop.type.value as ParameterType).value === 'string';
        callCode = `JSValue arr = JS_NewArray(ctx);
for(int i = 0; i <  ${bodyName}->${prop.name}Len; i ++) {
  JS_SetPropertyUint32(ctx, arr, i, ${generateQuickJSInitFromType(prop.type.value as ParameterType)}(ctx, ${isReference ? '&' : ''}${bodyName}->${prop.name}[i]));
}
JS_SetPropertyStr(ctx, object, "${prop.name}", arr);`
      } else {
        let targetTypes = Array.from(info.others).find(o => o.name === type.value);
        if (targetTypes) {
          generateTypeStringify(targetTypes, prop.name, info, externalInitialize);
          callCode = `JS_SetPropertyStr(ctx, object, "${prop.name}", stringify_property_${type.value}(ctx, ${bodyName}->${prop.name}));`
        }
      }
    }
    return callCode;
  }

  let callCode = genCallCode(prop.type, prop);

  return addIndent(prop.optional ? wrapIf(callCode) : callCode, 2);
}

function generateRequestParser(info: DAPInfoCollector, requests: string[], externalInitialize: string[]) {
  return requests.map(request => {
    let targetArgument = Array.from(info.arguments).find((ag) => {
      const prefix = ag.name.replace('Arguments', '');
      return request.indexOf(prefix) >= 0;
    });

    if (!targetArgument) {
      return '';
    }

    let parserCode: string[] = [];
    if (targetArgument.props) {
      targetArgument.props.forEach(prop => {
        let code = generatePropParser(prop, externalInitialize, info);
        if (code) {
          parserCode.push(code);
        }
      });
    }
    const name = request.replace('Request', '');
    return addIndent(`if (strcmp(command, "${_.camelCase(name)}") == 0) {
  ${name}Arguments* args = js_malloc(ctx, sizeof(${name}Arguments));
  ${parserCode.join('\n')}
  return args;
}`, 2);

  }).join('\n');
}


function generateEventInitializer(info: DAPInfoCollector, events: string[], externalInitialize: string[]) {
  return events.map(event => {
    let targetBody = Array.from(info.bodies).find((ag) => {
      const prefix = ag.name.replace('Body', '');
      return event.indexOf(prefix) >= 0;
    });

    if (!targetBody) {
      return '';
    }
    let bodyInitCode: string[] = [];
    if (targetBody.props) {
      targetBody.props.forEach(prop => {
        let code = generateMemberInit(prop, externalInitialize, info);
        if (code) {
          bodyInitCode.push(code);
        }
      });
    }
    return addIndent(`if (strcmp(event, "${_.camelCase(event.replace('Event', ''))}") == 0) {
  ${event}* result = js_malloc(ctx, sizeof(${event}));
  result->event = event;
  ${event}Body* body = js_malloc(ctx, sizeof(${event}Body));
${addIndent(bodyInitCode.join('\n'), 2)}
  result->body = body;
  return result;
}`, 2);

  }).join('\n');
}

function generateResponseInitializer(info: DAPInfoCollector, responses: string[], externalInitialize: string[]) {
  return responses.map(response => {
    let targetBody = Array.from(info.bodies).find((ag) => {
      const prefix = ag.name.replace('Body', '');
      return response.indexOf(prefix) >= 0;
    });

    if (!targetBody) {
      return '';
    }
    let bodyInitCode: string[] = [];
    if (targetBody.props) {
      targetBody.props.forEach(prop => {
        let code = generateMemberInit(prop, externalInitialize, info);
        if (code) {
          bodyInitCode.push(code);
        }
      });
    }
    return addIndent(`if (strcmp(response, "${_.camelCase(response.replace('Response', ''))}") == 0) {
  ${response}* result = js_malloc(ctx, sizeof(${response}));
  result->type = "response";
  result->seq = response_seq++;
  result->request_seq = corresponding_request->seq;
  result->command = corresponding_request->command;
  result->success = 1;
  result->message = NULL;
  ${response}Body* body = js_malloc(ctx, sizeof(${response}Body));
${addIndent(bodyInitCode.join('\n'), 2)}
  result->body = body;
  return result;
}`, 2);

  }).join('\n');
}

function generateEventBodyStringifyCode(info: DAPInfoCollector, events: string[], externalInitialize: string[]) {
  return events.map(event => {
    let targetBody = Array.from(info.bodies).find((ag) => {
      const prefix = ag.name.replace('Body', '');
      return event.indexOf(prefix) >= 0;
    });

    if (!targetBody) {
      return '';
    }

    let bodyStringifyCode: string[] = [];
    if (targetBody.props) {
      targetBody.props.forEach(prop => {
        let code = generateMemberStringifyCode(prop, `${_.snakeCase(event)}_body`, externalInitialize, info);
        if (code) {
          bodyStringifyCode.push(code);
        }
      });
    }
    return addIndent(`if (strcmp(event, "${_.camelCase(event.replace('Event', ''))}") == 0) {
  ${event}Body* ${_.snakeCase(event)}_body = (${event}Body*) body;
  ${bodyStringifyCode.join('\n')}
}`, 2);
  }).join('\n');
}

function generateResponseBodyStringifyCode(info: DAPInfoCollector, responses: string[], externalInitialize: string[]) {
  return responses.map(response => {
    let targetBody = Array.from(info.bodies).find((ag) => {
      const prefix = ag.name.replace('Body', '');
      return response.indexOf(prefix) >= 0;
    });

    if (!targetBody) {
      return '';
    }

    let bodyStringifyCode: string[] = [];
    if (targetBody.props) {
      targetBody.props.forEach(prop => {
        let code = generateMemberStringifyCode(prop, `${_.snakeCase(response)}_body`, externalInitialize, info);
        if (code) {
          bodyStringifyCode.push(code);
        }
      });
    }
    return addIndent(`if (strcmp(command, "${_.camelCase(response.replace('Response', ''))}") == 0) {
  ${response}Body* ${_.snakeCase(response)}_body = (${response}Body*) body;
  ${bodyStringifyCode.join('\n')}
}`, 2);
  }).join('\n');
}


export function generateDAPSource(info: DAPInfoCollector) {
  const requests: string[] = getLists(info.requests);
  const events: string[] = getLists(info.events);
  const responses: string[] = getLists(info.response);
  const externalInitialize: string[] = [];

  const requestParser = generateRequestParser(info, requests, externalInitialize);
  const eventInit = generateEventInitializer(info, events, externalInitialize);
  const responseInit = generateResponseInitializer(info, responses, externalInitialize);
  const eventBodyStringifyCode = generateEventBodyStringifyCode(info, events, externalInitialize);
  const responseBodyStringifyCode = generateResponseBodyStringifyCode(info, responses, externalInitialize);
  return _.template(readConverterTemplate())({
    info,
    requests,
    requestParser,
    eventInit,
    responseInit,
    eventBodyStringifyCode,
    responseBodyStringifyCode,
    externalInitialize
  }).split('\n').filter(str => {
    return str.trim().length > 0;
  }).join('\n');
}
