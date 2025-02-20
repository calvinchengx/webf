/*
 * Copyright (C) 2022-present The WebF authors. All rights reserved.
 */

#include "gtest/gtest.h"
#include "webf_test_env.h"

using namespace webf;

TEST(HTMLCollection, children) {
  bool static errorCalled = false;
  bool static logCalled = false;
  webf::WebFPage::consoleMessageHandler = [](void* ctx, const std::string& message, int logLevel) {
    EXPECT_STREQ(message.c_str(), "2 <div/> <p/>");
    logCalled = true;
  };
  auto env = TEST_init([](int32_t contextId, const char* errmsg) {
    WEBF_LOG(VERBOSE) << errmsg;
    errorCalled = true;
  });
  auto context = env->page()->GetExecutingContext();
  const char* code =
      "let div = document.createElement('div');"
      "let text = document.createTextNode('1234');"
      "let div2 = document.createElement('p');"
      "document.body.appendChild(div);"
      "document.body.appendChild(text);"
      "document.body.appendChild(div2);"
      "console.log(document.body.children.length, document.body.children[0], document.body.children[1]);";
  env->page()->evaluateScript(code, strlen(code), "vm://", 0);

  EXPECT_EQ(errorCalled, false);
}
