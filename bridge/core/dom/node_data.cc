/*
 * Copyright (C) 2019-2022 The Kraken authors. All rights reserved.
 * Copyright (C) 2022-present The WebF authors. All rights reserved.
 */

#include "node_data.h"
#include "bindings/qjs/cppgc/garbage_collected.h"
#include "child_node_list.h"
#include "container_node.h"
#include "empty_node_list.h"
#include "node_list.h"

namespace webf {

ChildNodeList* NodeData::GetChildNodeList(ContainerNode& node) {
  assert(!child_node_list_ || &node == child_node_list_->VirtualOwnerNode());
  return To<ChildNodeList>(child_node_list_.Get());
}

ChildNodeList* NodeData::EnsureChildNodeList(ContainerNode& node) {
  if (child_node_list_)
    return To<ChildNodeList>(child_node_list_.Get());
  auto* list = MakeGarbageCollected<ChildNodeList>(&node);
  child_node_list_ = list;
  return list;
}

EmptyNodeList* NodeData::EnsureEmptyChildNodeList(Node& node) {
  if (child_node_list_)
    return To<EmptyNodeList>(child_node_list_.Get());
  auto* list = MakeGarbageCollected<EmptyNodeList>(&node);
  child_node_list_ = list;
  return list;
}

void NodeData::Trace(GCVisitor* visitor) const {
  if (child_node_list_ != nullptr) {
    visitor->Trace(child_node_list_->ToQuickJSUnsafe());
  }
}

}  // namespace webf
