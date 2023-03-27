/*
 * Copyright (C) 2019-2022 The Kraken authors. All rights reserved.
 * Copyright (C) 2022-present The WebF authors. All rights reserved.
 */

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:ffi';

import 'package:webf/webf.dart';
import 'package:webf/devtools.dart';
import 'package:ffi/ffi.dart';

const String CONTENT_TYPE = 'Content-Type';
const String CONTENT_LENGTH = 'Content-Length';
const String FAVICON = 'https://gw.alicdn.com/tfs/TB1tTwGAAL0gK0jSZFxXXXWHVXa-144-144.png';

class DebuggerMessageBuffer extends Struct {
  external Pointer<Utf8> buffer;

  @Uint32()
  external int length;
}

class JavaScriptDebuggerMethods extends Struct {
  // The debugger backend implement this methods to receive commands from devtools client.
  external Pointer<NativeFunction<NativeDebuggerWriteFrontEndCommands>> writeFrontEndCommands;
  // The devtools client implement this methods to receive commands from debugger backend.
  external Pointer<NativeFunction<NativeDebuggerReadBackendCommands>> readBackendCommands;
  // The devtools client implement this methods to receive notifications when the debugger backend shutdown.
  external Pointer<NativeFunction<NativeDebuggerOnBackendShutdown>> onBackendShutdown;
}

typedef MessageCallback = void Function(Map<String, dynamic>?);

typedef NativeDebuggerWriteFrontEndCommands = Uint32 Function(Pointer<Void> debuggerContext, Pointer<DebuggerMessageBuffer> message);
typedef DartDebuggerWriteFrontEndCommands = int Function(Pointer<Void> debuggerContext, Pointer<DebuggerMessageBuffer> message);
typedef NativeDebuggerReadBackendCommands = Uint32 Function(Pointer<Void> debuggerContext, Pointer<DebuggerMessageBuffer> message);
typedef DartDebuggerReadBackendCommands = int Function(Pointer<Void> debuggerContext, Pointer<DebuggerMessageBuffer> message);
typedef NativeDebuggerOnBackendShutdown = Void Function(Pointer<Void> runtime, Pointer<Void> debuggerContext);

typedef NativeAttachDebugger = Pointer<Void> Function(Pointer<Void> jsContext, Pointer<JavaScriptDebuggerMethods> debuggerMethods);
typedef DartAttachDebugger = Pointer<Void> Function(Pointer<Void> jsContext, Pointer<JavaScriptDebuggerMethods> debuggerMethods);

// The debug server are running separated thread.
// This is the main function when the isolate thread started.
void serverIsolateEntryPoint(SendPort isolateToMainStream) {
  ReceivePort mainToIsolateStream = ReceivePort();
  isolateToMainStream.send(mainToIsolateStream.sendPort);
  IsolateInspector? inspector;
  // Callbacks when receive data from main thread.
  mainToIsolateStream.listen((data) {
    handleChromeDevToolsMessage(Map<String, dynamic>? frontEndMessage) {
      int? id = frontEndMessage!['id'];
      String _method = frontEndMessage['method'];
      Map<String, dynamic>? params = frontEndMessage['params'];

      List<String> moduleMethod = _method.split('.');
      String module = moduleMethod[0];
      String method = moduleMethod[1];

      // Runtime、Log、Debugger methods should handled on inspector isolate.
      if (module == 'Runtime' || module == 'Log' || module == 'Debugger') {
        // Convert CDP Protocol message to DAP
        // Send DAP Protocol message to Debugger
        // server!.messageRouter(id, module, method, params);
      } else {
        isolateToMainStream.send(InspectorFrontEndMessage(id, module, method, params));
      }
      isolateToMainStream.send(DebuggerAttachedEvent());
    }

    handleVsCodeExtensionMessage (Map<String, dynamic>? message) {
      if (message != null) {
        inspector!.sendDapMessageToDebugger(message);
      }
      isolateToMainStream.send(DebuggerAttachedEvent());
      isolateToMainStream.send(NewFrontEndMessageEvent());
    }

    // Init the dev server
    if (data is InspectorServerInit) {
      IsolateInspectorServer server = IsolateInspectorServer(data.port, data.address, data.bundleURL, data.jsContextAddr);
      server.onStarted = () {
        // Tell the main thread the dev server started.
        isolateToMainStream.send(InspectorServerStart(server.port));
      };
      // Receive message from Chrome DevTools.
      server.onChromeDevToolsMessage = handleChromeDevToolsMessage;
      // Receive message from WebF VSCode extension.
      server.onVsCodeExtensionMessage = handleVsCodeExtensionMessage;
      server.start();
      inspector = server;
    } else if (data is InspectorServerConnect) {
      IsolateInspectorClient client = IsolateInspectorClient(data.url, data.jsContextAddress);
      client.onStarted = () {
        isolateToMainStream.send(InspectorClientConnected());
      };
      client.onChromeDevToolsMessage = handleChromeDevToolsMessage;
      client.onVsCodeExtensionMessage = handleVsCodeExtensionMessage;
      client.start();
      inspector = client;
    } else if (inspector != null && inspector!.connected) {
      if (data is InspectorEvent) {
        inspector!.sendEventToFrontend(data);
      } else if (data is InspectorMethodResult) {
        inspector!.sendToFrontend(data.id, data.result);
      }
    }
  });
}

enum ConnectionClientKind {
  // The client is WebF vscode extension. DOM/CSS/Network debug features are disabled.
  vscode,
  // The client is Chrome devtools, all features are enabled.
  chromeDevTools
}

class IsolateInspector {
  static void attachDebugger(Pointer<Void> JSContext, Pointer<JavaScriptDebuggerMethods> debuggerMethods, IsolateInspector inspector) {
    final DartAttachDebugger _attachInspector = WebFDynamicLibrary.ref.lookup<NativeFunction<NativeAttachDebugger>>('attachDebugger').asFunction();
    inspector.debuggerContext = _attachInspector(JSContext, debuggerMethods);
  }

  ConnectionClientKind? clientKind;

  static void _initDebuggerMethods(IsolateInspector inspector, Pointer<JavaScriptDebuggerMethods> debuggerMethods) {
    // Set to nullptr and waiting for debugger backend to rewrite this methods.
    debuggerMethods.ref.writeFrontEndCommands = nullptr;
    debuggerMethods.ref.readBackendCommands = nullptr;
    debuggerMethods.ref.onBackendShutdown = nullptr;
  }

  static void _onDebuggerBackendShutdown(Pointer<Void> runtime, Pointer<Void> debuggerContext) {

  }

  IsolateInspector(this.jsContextAddress) {
    _initDebuggerMethods(this, debuggerMethods);
  }

  bool _disposed = false;

  int jsContextAddress;
  VoidCallback? onStarted;
  MessageCallback? onChromeDevToolsMessage;
  MessageCallback? onVsCodeExtensionMessage;

  final Queue<String> _pendingDebuggerMessages = Queue();

  // Native methods shared between client and debugger backend.
  Pointer<JavaScriptDebuggerMethods> debuggerMethods = malloc.allocate(sizeOf<JavaScriptDebuggerMethods>());
  Pointer<Void> debuggerContext = nullptr;

  final Map<String, IsolateInspectorModule> moduleRegistrar = {};

  WebSocket? _ws;
  WebSocket? get ws => _ws;
  bool get connected => false;

  void messageRouter(int? id, String module, String method, Map<String, dynamic>? params) {
    if (moduleRegistrar.containsKey(module)) {
      moduleRegistrar[module]!.invoke(id, method, params);
    }
  }

  // The JavaScript Debugger only accept DAP protocol debug messages.
  void sendDapMessageToDebugger(Map<String, dynamic> message) {
    assert(debuggerContext != nullptr);

    print('send message to debugger: $message');

    // Write commands to Debugger Backend.
    DartDebuggerWriteFrontEndCommands fn = debuggerMethods.ref.writeFrontEndCommands.asFunction();
    Pointer<Utf8> nativeStr = jsonEncode(message).toNativeUtf8();
    Pointer<DebuggerMessageBuffer> buffer = malloc.allocate(sizeOf<DebuggerMessageBuffer>());
    buffer.ref.buffer = nativeStr;
    buffer.ref.length = nativeStr.length;
    fn(debuggerContext, buffer);

    malloc.free(nativeStr);
    malloc.free(buffer);
  }

  // Receive DAP protocol commands from JavaScript Debugger backend every microtask.
  void readDebuggerBackendMessage() {
    if (_disposed) return;

    assert(debuggerMethods.ref.readBackendCommands != nullptr);

    DartDebuggerReadBackendCommands fn = debuggerMethods.ref.readBackendCommands.asFunction();
    if (fn != nullptr) {
      Pointer<DebuggerMessageBuffer> message = malloc.allocate(sizeOf<DebuggerMessageBuffer>());
      int result = fn(debuggerContext, message);
      if (result == 0) {
        malloc.free(message);
        Timer(Duration(milliseconds: 1), readDebuggerBackendMessage);
        return;
      }
      String str = message.ref.buffer.toDartString(length: message.ref.length);
      if (_ws != null) {
        if (clientKind == ConnectionClientKind.vscode) {
          _ws?.add(str);
        } else {
          // TODO: Add adaptor from DAP to CDP..
        }
      } else {
        _pendingDebuggerMessages.add(str);
      }
      malloc.free(message.ref.buffer);
      malloc.free(message);
    }

    Timer(Duration(milliseconds: 1), readDebuggerBackendMessage);
  }

  void _flushPendingDebuggerMessage() {
    assert(_ws != null);
    while(_pendingDebuggerMessages.isNotEmpty) {
      String first = _pendingDebuggerMessages.removeFirst();
      _ws!.add(first);
    }
  }

  void registerModule(IsolateInspectorModule module) {
    moduleRegistrar[module.name] = module;
  }

  void sendToFrontend(int? id, Map? result) {
    if (clientKind == ConnectionClientKind.chromeDevTools) {
      String data = jsonEncode({
        if (id != null) 'id': id,
        // Give an empty object for response.
        'result': result ?? {},
      });
      _ws?.add(data);
    }
  }

  void sendEventToFrontend(InspectorEvent event) {
    if (clientKind == ConnectionClientKind.chromeDevTools) {
      _ws?.add(jsonEncode(event));
    }
  }

  void dispose() async {
    onVsCodeExtensionMessage = null;
    onChromeDevToolsMessage = null;
  }

  Map<String, dynamic>? _parseMessage(message) {
    try {
      Map<String, dynamic>? data = jsonDecode(message);
      return data;
    } catch (err) {
      print('Error while decoding frontend message: $message');
      rethrow;
    }
  }

  void sendMessageToChromeDevTools(int? id, Map? result) {
    if (clientKind == ConnectionClientKind.chromeDevTools) {
      String data = jsonEncode({
        if (id != null) 'id': id,
        // Give an empty object for response.
        'result': result ?? {},
      });
      _ws?.add(data);
    }
  }

  void sendEventToChromeDevTools(InspectorEvent event) {
    if (clientKind == ConnectionClientKind.chromeDevTools) {
      _ws?.add(jsonEncode(event));
    }
  }

  void onWebSocketRequest(message) {
    if (message is String) {
      Map<String, dynamic>? data = _parseMessage(message);
      print('receive data: $data');
      // Handle messages from WebF Vscode plugin.
      if (data != null && data['vscode'] && onVsCodeExtensionMessage != null) {
        clientKind = ConnectionClientKind.vscode;
        onVsCodeExtensionMessage!(data['data']);
        // Handle message from Chrome DevTools.
      } else if (onChromeDevToolsMessage != null) {
        onChromeDevToolsMessage!(data);
        clientKind = ConnectionClientKind.chromeDevTools;
      }
    }
  }
}

class IsolateInspectorServer extends IsolateInspector {
  IsolateInspectorServer(this.port, this.address, this.bundleURL, super.jsContextAddress);

  // final Inspector inspector;
  final String address;
  final String bundleURL;
  int port;

  VoidCallback? onStarted;
  late HttpServer _httpServer;

  /// InspectServer has connected frontend.
  @override
  bool get connected => _ws?.readyState == WebSocket.open;

  int _bindServerRetryTime = 0;

  Future<void> _bindServer(int port) async {
    // print('bind server: $address $port');
    try {
      _httpServer = await HttpServer.bind(address, port);
      this.port = port;
    } on SocketException {
      if (_bindServerRetryTime < 10) {
        _bindServerRetryTime++;
        await _bindServer(port + 1);
      } else {
        rethrow;
      }
    }
  }

  Future<void> start() async {
    await _bindServer(port);

    if (onStarted != null) {
      onStarted!();
    }

    _httpServer.listen((HttpRequest request) {
      IsolateInspector.attachDebugger(Pointer.fromAddress(jsContextAddress), debuggerMethods, this);
      readDebuggerBackendMessage();
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        WebSocketTransformer.upgrade(request, compression: CompressionOptions.compressionOff)
            .then((WebSocket webSocket) {
          _ws = webSocket;
          webSocket.listen(onWebSocketRequest, onDone: () {
            _ws = null;
          }, onError: (obj, stack) {
            _ws = null;
          });
          _flushPendingDebuggerMessage();
        });
      } else {
        onHTTPRequest(request);
      }
    });
  }

  Future<void> onHTTPRequest(HttpRequest request) async {
    switch (request.requestedUri.path) {
      case '/json/version':
        onRequestVersion(request);
        break;

      case '/json':
      case '/json/list':
        onRequestList(request);
        break;

      case '/json/new':
        onRequestNew(request);
        break;

      case '/json/close':
        onRequestClose(request);
        break;

      case '/json/protocol':
        onRequestProtocol(request);
        break;

      default:
        onRequestFallback(request);
        break;
    }
    await request.response.close();
  }

  void _writeJSONObject(HttpRequest request, Object obj) {
    String body = jsonEncode(obj);
    // Must preserve header case, or chrome devtools inspector will drop data.
    request.response.headers.set(CONTENT_TYPE, 'application/json; charset=UTF-8', preserveHeaderCase: true);
    request.response.headers.set(CONTENT_LENGTH, body.length, preserveHeaderCase: true);
    request.response.write(body);
  }

  void onRequestVersion(HttpRequest request) {
    request.response.headers.clear();
    _writeJSONObject(request, {
      'Browser': '${NavigatorModule.getAppName()}/${NavigatorModule.getAppVersion()}',
      'Protocol-Version': '1.3',
      'User-Agent': NavigatorModule.getUserAgent(),
    });
  }

  void onRequestList(HttpRequest request) {
    request.response.headers.clear();
    String pageId = hashCode.toString();
    String entryURL = '$address:$port/devtools/page/$pageId';
    _writeJSONObject(request, [
      {
        'faviconUrl': FAVICON,
        'devtoolsFrontendUrl': '$INSPECTOR_URL?ws=$entryURL',
        'title': 'WebF App',
        'id': pageId,
        'type': 'page',
        'url': bundleURL,
        'webSocketDebuggerUrl': 'ws://$entryURL'
      }
    ]);
  }

  void onRequestClose(HttpRequest request) {
    onRequestFallback(request);
  }

  void onRequestActivate(HttpRequest request) {
    onRequestFallback(request);
  }

  void onRequestNew(HttpRequest request) {
    onRequestFallback(request);
  }

  void onRequestProtocol(HttpRequest request) {
    onRequestFallback(request);
  }

  void onRequestFallback(HttpRequest request) {
    request.response.statusCode = 404;
    request.response.write('Unknown request.');
  }

  @override
  void dispose() async {
    super.dispose();
    _disposed = true;
    onStarted = null;
    onChromeDevToolsMessage = null;
    onVsCodeExtensionMessage = null;

    await _ws?.close();
    await _httpServer.close();
  }
}

class IsolateInspectorClient extends IsolateInspector {
  final String url;

  IsolateInspectorClient(this.url, super.jsContextAddress);

  @override
  bool get connected => _ws?.readyState == WebSocket.open;

  VoidCallback? onStarted;

  void start() async {
    _ws = await WebSocket.connect(url, protocols: ['echo-protocol']);
    _ws!.listen((data) {
      onWebSocketRequest(data);
    });
  }
}
