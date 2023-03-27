/*
 * Copyright (C) 2019-2022 The Kraken authors. All rights reserved.
 * Copyright (C) 2022-present The WebF authors. All rights reserved.
 */
#ifndef BRIDGE_NATIVE_STRING_H
#define BRIDGE_NATIVE_STRING_H

#include <quickjs/quickjs.h>
#include <cinttypes>
#include <cstdlib>
#include <cstring>
#include <memory>

#include "foundation/macros.h"

namespace webf {

// SharedNativeString is a container class that accepts allocated UTF-16 strings,
// and users are responsible for freeing their strings
struct SharedNativeString {
  SharedNativeString(const uint16_t* string, uint32_t length);
  static std::unique_ptr<SharedNativeString> FromTemporaryString(const uint16_t* string, uint32_t length);

  inline const uint16_t* string() const { return string_; }
  inline uint32_t length() const { return length_; }

  void free() const { delete[] string_; }

 protected:
  SharedNativeString() = default;
  const uint16_t* string_;
  uint32_t length_;
};

// NativeString is a container class that accepts allocated on Heap UTF-16 strings,
// and freeing strings by itself.
struct AutoFreeNativeString : public SharedNativeString {
 public:
  ~AutoFreeNativeString();
};

}  // namespace webf

#endif  // BRIDGE_NATIVE_STRING_H
