/*
 * Copyright (C) 2022-present The WebF authors. All rights reserved.
 */

#include "computed_css_style_declaration.h"
#include "binding_call_methods.h"
#include "core/dom/element.h"
#include "foundation/native_value_converter.h"

namespace webf {

ComputedCssStyleDeclaration::ComputedCssStyleDeclaration(ExecutingContext* context,
                                                         NativeBindingObject* native_binding_object)
    : CSSStyleDeclaration(context->ctx()), BindingObject(context, native_binding_object) {}

AtomicString ComputedCssStyleDeclaration::item(const AtomicString& key, ExceptionState& exception_state) {
  NativeValue arguments[] = {NativeValueConverter<NativeTypeString>::ToNativeValue(ctx(), key)};

  NativeValue result = InvokeBindingMethod(binding_call_methods::kgetPropertyValue, 1, arguments, exception_state);
  return NativeValueConverter<NativeTypeString>::FromNativeValue(ctx(), result);
}

bool ComputedCssStyleDeclaration::SetItem(const AtomicString& key,
                                          const AtomicString& value,
                                          ExceptionState& exception_state) {
  NativeValue arguments[] = {NativeValueConverter<NativeTypeString>::ToNativeValue(ctx(), key),
                             NativeValueConverter<NativeTypeString>::ToNativeValue(ctx(), value)};
  InvokeBindingMethod(binding_call_methods::ksetProperty, 2, arguments, exception_state);
  return true;
}

int64_t ComputedCssStyleDeclaration::length() const {
  NativeValue result = GetBindingProperty(binding_call_methods::klength, ASSERT_NO_EXCEPTION());
  return NativeValueConverter<NativeTypeInt64>::FromNativeValue(result);
}

AtomicString ComputedCssStyleDeclaration::getPropertyValue(const AtomicString& key, ExceptionState& exception_state) {
  return item(key, exception_state);
}

void ComputedCssStyleDeclaration::setProperty(const AtomicString& key,
                                              const AtomicString& value,
                                              ExceptionState& exception_state) {
  SetItem(key, value, exception_state);
}

AtomicString ComputedCssStyleDeclaration::removeProperty(const AtomicString& key, ExceptionState& exception_state) {
  NativeValue arguments[] = {NativeValueConverter<NativeTypeString>::ToNativeValue(ctx(), key)};
  NativeValue result = InvokeBindingMethod(binding_call_methods::kremoveProperty, 1, arguments, exception_state);
  return NativeValueConverter<NativeTypeString>::FromNativeValue(ctx(), result);
}

bool ComputedCssStyleDeclaration::NamedPropertyQuery(const AtomicString& key, ExceptionState& exception_state) {
  NativeValue arguments[] = {NativeValueConverter<NativeTypeString>::ToNativeValue(ctx(), key)};
  NativeValue result = InvokeBindingMethod(binding_call_methods::kcheckCSSProperty, 1, arguments, exception_state);
  return NativeValueConverter<NativeTypeBool>::FromNativeValue(result);
}

void ComputedCssStyleDeclaration::NamedPropertyEnumerator(std::vector<AtomicString>& names,
                                                          ExceptionState& exception_state) {
  NativeValue result = InvokeBindingMethod(binding_call_methods::kgetFullCSSPropertyList, 0, nullptr, exception_state);
  auto&& arr = NativeValueConverter<NativeTypeArray<NativeTypeString>>::FromNativeValue(ctx(), result);
  for (auto& i : arr) {
    names.emplace_back(i);
  }
}

bool ComputedCssStyleDeclaration::IsComputedCssStyleDeclaration() const {
  return true;
}

NativeValue ComputedCssStyleDeclaration::HandleCallFromDartSide(const NativeValue* method,
                                                                int32_t argc,
                                                                const NativeValue* argv) {
  return Native_NewNull();
}

}  // namespace webf