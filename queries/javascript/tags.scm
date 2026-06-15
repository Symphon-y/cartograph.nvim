; cartograph bundled tags query (javascript)
; Minimal, robust: only the captures cartograph.repo consumes
; (@name + @definition.* / @reference.call). No doc/strip directives so it
; parses under bare vim.treesitter without nvim-treesitter's custom predicates.

(function_declaration
  name: (identifier) @name) @definition.function

(generator_function_declaration
  name: (identifier) @name) @definition.function

(class_declaration
  name: (_) @name) @definition.class

(method_definition
  name: (property_identifier) @name) @definition.method

(variable_declarator
  name: (identifier) @name
  value: (arrow_function)) @definition.function

(variable_declarator
  name: (identifier) @name
  value: (function_expression)) @definition.function

(pair
  key: (property_identifier) @name
  value: (arrow_function)) @definition.function

(call_expression
  function: (identifier) @name) @reference.call

(call_expression
  function: (member_expression
    property: (property_identifier) @name)) @reference.call
