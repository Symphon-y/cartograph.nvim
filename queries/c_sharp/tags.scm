; cartograph bundled tags query (c_sharp)

(class_declaration
  name: (identifier) @name) @definition.class

(interface_declaration
  name: (identifier) @name) @definition.interface

(struct_declaration
  name: (identifier) @name) @definition.struct

(enum_declaration
  name: (identifier) @name) @definition.enum

(record_declaration
  name: (identifier) @name) @definition.class

(method_declaration
  name: (identifier) @name) @definition.method

(constructor_declaration
  name: (identifier) @name) @definition.method

(property_declaration
  name: (identifier) @name) @definition.field

(invocation_expression
  function: (identifier) @name) @reference.call

(invocation_expression
  function: (member_access_expression
    name: (identifier) @name)) @reference.call
