"""Compile the restricted canonical OCaml validator AST to Rust predicates.

Unsupported syntax and calls fail generation. Runtime code never interprets
this AST, and property rules have no separately maintained Rust matrix.
"""
import json
import re


def quote(value):
    return re.sub(r"\\u([0-9a-fA-F]{4})", r"\\u{\1}", json.dumps(value, ensure_ascii=False)).replace("\\b", "\\u{8}").replace("\\f", "\\u{c}")


def tail(code):
    return code[1:-1] if code.startswith("(") and code.endswith(")") else code


class Compiler:
    def __init__(self, schema):
        self.names = {p["lg"]: p["wire"] for p in schema["properties"]}
        self.names.update({k["lg"]: k["wire"] for k in schema["nodeKinds"]})
        self.functions = set()

    def pattern(self, pattern, typ):
        if "any" in pattern:
            return "_", {}
        if "var" in pattern:
            return pattern["var"], {pattern["var"]: typ}
        if "or" in pattern:
            a, ae = self.pattern(pattern["or"][0], typ)
            b, be = self.pattern(pattern["or"][1], typ)
            if ae != be:
                raise ValueError("inconsistent alternative pattern bindings")
            return a + " | " + b, ae
        if "tuple" in pattern:
            if not isinstance(typ, tuple) or len(typ) != len(pattern["tuple"]):
                raise ValueError("canonical tuple pattern type mismatch")
            items, bindings = [], {}
            for p, t in zip(pattern["tuple"], typ):
                code, env = self.pattern(p, t)
                items.append(code)
                bindings.update(env)
            return "(" + ", ".join(items) + ")", bindings
        if "constructor" in pattern:
            name = pattern["constructor"]
            if name == "None":
                return "None", {}
            constructors = {"Some": ("Some", "Scalar"), "StringValue": ("Scalar::String", "&str"),
                            "IntValue": ("Scalar::Int", "i64"), "FloatValue": ("Scalar::Float", "f64"),
                            "BoolValue": ("Scalar::Bool", "bool")}
            if name in constructors:
                constructor, argument_type = constructors[name]
                argument, env = self.pattern(pattern["argument"], argument_type)
                return f"{constructor}({argument})", env
            if name in self.names:
                return quote(self.names[name]), {}
            raise ValueError("unknown canonical pattern constructor " + name)
        code, _ = self.expr(pattern, {})
        return code, {}

    def expr(self, expression, env):
        if "number" in expression:
            number = expression["number"].replace("_", "")
            typ = "f64" if any(c in number for c in ".eE") else "i64"
            if number.endswith("."):
                number += "0"
            return number + "_" + typ, typ
        if "string" in expression:
            return quote(expression["string"]), "&str"
        if "presence" in expression:
            return "presence_supported(kind, properties)", "bool"
        if "ident" in expression:
            name = expression["ident"]
            if name in env:
                return name, env[name]
            constants = {"infinity": "f64::INFINITY", "neg_infinity": "f64::NEG_INFINITY", "Float.max_float": "f64::MAX"}
            if name in constants:
                return constants[name], "f64"
            raise ValueError("unknown canonical identifier " + name)
        if "constructor" in expression:
            name = expression["constructor"]
            if name in ("true", "false"):
                return name, "bool"
            if name in ("[]", "::"):
                items, current = [], expression
                while current.get("constructor") == "::":
                    head, current = current["argument"]["tuple"]
                    item, typ = self.expr(head, env)
                    if typ != "&str":
                        raise ValueError("canonical list must contain strings")
                    items.append(item)
                if current.get("constructor") != "[]":
                    raise ValueError("canonical list requires a literal tail")
                return "&[" + ", ".join(items) + "]", "&[&str]"
            scalar = {"StringValue": "String", "IntValue": "Int", "FloatValue": "Float", "BoolValue": "Bool"}
            if name in scalar:
                value, _ = self.expr(expression["argument"], env)
                return f"Scalar::{scalar[name]}({value})", "Scalar"
            if name in self.names:
                return quote(self.names[name]), "&str"
            raise ValueError("unknown canonical constructor " + name)
        if "tuple" in expression:
            items = [self.expr(item, env) for item in expression["tuple"]]
            return "(" + ", ".join(code for code, _ in items) + ")", tuple(typ for _, typ in items)
        if "if" in expression:
            condition, condition_type = self.expr(expression["if"], env)
            yes, typ = self.expr(expression["then"], env)
            no, no_type = self.expr(expression["else"], env)
            if condition_type != "bool" or typ != no_type:
                raise ValueError("canonical conditional type mismatch")
            return f"if {tail(condition)} {{ {tail(yes)} }} else {{ {tail(no)} }}", typ
        if "let" in expression:
            local, declarations = dict(env), []
            for binding in expression["let"]:
                value, typ = self.expr(binding["value"], local)
                name = binding["pattern"].get("var")
                if name is None:
                    raise ValueError("canonical let requires a variable")
                declarations.append(f"let {name} = {tail(value)};")
                local[name] = typ
            body, typ = self.expr(expression["body"], local)
            return "{ " + " ".join(declarations) + " " + tail(body) + " }", typ
        if "match" in expression:
            value, typ = self.expr(expression["match"], env)
            cases = expression["cases"]
            if (len(cases) >= 2 and cases[-1]["pattern"] == {"any": True}
                    and cases[-1]["value"] == {"constructor": "false"}
                    and all(case["value"] == {"constructor": "true"} for case in cases[:-1])):
                def unbound(pattern):
                    if "var" in pattern:
                        return {"any": True}
                    return {key: ([unbound(item) for item in item_value] if isinstance(item_value, list)
                                  else unbound(item_value) if isinstance(item_value, dict) else item_value)
                            for key, item_value in pattern.items()}
                patterns = [self.pattern(unbound(case["pattern"]), typ)[0] for case in cases[:-1]]
                return f"matches!({value}, {' | '.join(patterns)})", "bool"
            branches, result_type = [], None
            for case in cases:
                pattern, bindings = self.pattern(case["pattern"], typ)
                body, branch_type = self.expr(case["value"], {**env, **bindings})
                if result_type is not None and result_type != branch_type:
                    raise ValueError("canonical match branch type mismatch")
                result_type = branch_type
                branches.append(f"{pattern} => {{ {tail(body)} }},")
            return f"match {value} {{ {' '.join(branches)} }}", result_type
        if "call" in expression:
            name = expression["call"].get("ident")
            if name in ("&&", "||"):
                operands = []
                def collect(current):
                    if current.get("call", {}).get("ident") == name:
                        for argument in current["args"]:
                            collect(argument)
                    else:
                        operands.append(current)
                collect(expression)
                pieces, index = [], 0
                while index < len(operands):
                    current = operands[index]
                    following = operands[index + 1] if index + 1 < len(operands) else {}
                    if (name == "&&" and current.get("call", {}).get("ident") == ">="
                            and following.get("call", {}).get("ident") == "<="
                            and current["args"][0] == following["args"][0]
                            and "ident" in current["args"][0]
                            and "number" in current["args"][1]
                            and "number" in following["args"][1]):
                        value, value_type = self.expr(current["args"][0], env)
                        lower, lower_type = self.expr(current["args"][1], env)
                        upper, upper_type = self.expr(following["args"][1], env)
                        if value_type != lower_type or value_type != upper_type:
                            raise ValueError("canonical range type mismatch")
                        pieces.append(f"({lower}..={upper}).contains(&{value})")
                        index += 2
                        continue
                    code, typ = self.expr(current, env)
                    if typ != "bool":
                        raise ValueError("canonical boolean operand type mismatch")
                    if code.startswith(("if ", "match ", "{ ")):
                        code = "(" + code + ")"
                    pieces.append(code)
                    index += 1
                return "(" + (" " + name + " ").join(pieces) + ")", "bool"
            args = [self.expr(arg, env) for arg in expression["args"]]
            values = [code for code, _ in args]
            operators = {"=": "==", "<>": "!=", ">=": ">=", "<=": "<=", ">": ">", "<": "<", "+": "+", "&&": "&&", "||": "||"}
            if name in operators:
                if len(args) != 2 or args[0][1] != args[1][1]:
                    raise ValueError("canonical operator type mismatch: " + str((name, args)))
                if name in ("=", "<>") and args[0][1] == "&str" and (values[0] == '""' or values[1] == '""'):
                    value = values[1] if values[0] == '""' else values[0]
                    return ("!" if name == "<>" else "") + value + ".is_empty()", "bool"
                if values[0] == values[1] and args[0][1] == "f64" and name == "=":
                    return f"!{values[0]}.is_nan()", "bool"
                return f"({values[0]} {operators[name]} {values[1]})", args[0][1] if name == "+" else "bool"
            if name == "not":
                return f"!({tail(values[0])})", "bool"
            if name == "Option.is_some":
                return f"{values[0]}.is_some()", "bool"
            special = {
                "Property_map.mem": ("contains_property", "bool"), "Property_map.find_opt": ("lookup", "Option<Scalar>"),
                "String.trim": ("ocaml_trim", "&str"), "List.mem": ("contains", "bool"),
                "true_property": ("true_property", "bool"), "treeitem_properties": ("treeitem_properties", "bool"),
                "tree_row_kind": ("tree_row_kind", "bool"), "int_property": ("int_property", "i64"),
                "float_property": ("float_property", "f64"), "float_property_of": ("float_property", "f64"),
                "string_property_or": ("string_property_or", "&str"), "string_property_nonempty": ("string_property_nonempty", "bool"),
                "surface_size_supported": ("surface_size_supported", "bool"), "viewport_size_supported": ("viewport_size_supported", "bool"),
                "icon_name_supported": ("icon_name_supported", "bool"), "anchor_rect_of_string": ("anchor_rect_of_string", "Option<()>"),
                "data_attrs_value_ok": ("data_attrs_value_ok", "bool"), "element_tag_known": ("element_tag_known", "bool"),
                "element_tag_supported": ("element_tag_supported", "bool"), "text_decoration_supported": ("text_decoration_supported", "bool"),
                "transition_supported": ("transition_supported", "bool"), "virtual_indices_of_string": ("virtual_indices_of_string", "Option<Vec<i64>>")}
            if name in special:
                target, typ = special[name]
            elif name in self.functions:
                target, typ = name, "bool"
            else:
                raise ValueError("unsupported canonical call " + str(name))
            return f"{target}({', '.join(values)})", typ
        raise ValueError("unsupported canonical expression " + repr(expression))


def scalar_types(schema, contract):
    """Infer scalar alternatives from canonical patterns, never sample values."""
    validator = contract["validators"]["property_value_supported"]
    if validator.get("match") != {"tuple": [{"ident": "property"}, {"ident": "value"}]}:
        raise ValueError("canonical scalar validator requires a property/value match")
    constructors = {"string": "StringValue", "bool": "BoolValue", "int": "IntValue", "float": "FloatValue"}

    def accepts(pattern, actual):
        if "any" in pattern or "var" in pattern:
            return True
        if "or" in pattern:
            return any(accepts(part, actual) for part in pattern["or"])
        if "tuple" in pattern:
            return "tuple" in actual and len(pattern["tuple"]) == len(actual["tuple"]) and all(
                accepts(part, value) for part, value in zip(pattern["tuple"], actual["tuple"]))
        if "constructor" in pattern:
            if pattern["constructor"] != actual.get("constructor"):
                return False
            return "argument" not in pattern or accepts(pattern["argument"], actual["argument"])
        if "string" in pattern:
            return actual == {"type": "string"}
        if "number" in pattern:
            return actual.get("type") in ("int", "float")
        raise ValueError("unsupported canonical scalar type pattern " + repr(pattern))

    output = {}
    for prop in schema["properties"]:
        alternatives = []
        for scalar, constructor in constructors.items():
            actual = {"tuple": [{"constructor": prop["lg"]},
                                  {"constructor": constructor, "argument": {"type": scalar}}]}
            if any(case["value"] != {"constructor": "false"} and accepts(case["pattern"], actual)
                   for case in validator["cases"]):
                alternatives.append(scalar)
        output[prop["wire"]] = alternatives
    return output


def compile_closed_domains(domains):
    """Compile selected provider enums from the canonical typed constructor export."""
    selected = {"virtual-viewport": "VirtualViewportValue", "display": "DisplayValue", "image-fit": "ImageFitValue",
                "container-relative-frame": "FrameAxesValue", "anchor": "AnchorValue",
                "anchor-alignment": "AnchorAlignmentValue", "orientation": "OrientationValue", "input-type": "InputTypeValue"}
    output = []
    for property_name, name in selected.items():
        values = domains.get(property_name)
        if not isinstance(values, list) or not values:
            raise ValueError("missing or invalid canonical closed domain: " + property_name)
        if any(not isinstance(value, str) or not re.fullmatch(r"[a-z][a-z0-9]*(?:-[a-z0-9]+)*", value) for value in values):
            raise ValueError("unsupported canonical enum spelling: " + property_name)
        if len(set(values)) != len(values):
            raise ValueError("duplicate canonical enum values: " + property_name)
        variants = [(value, "".join(part[0].upper() + part[1:] for part in value.split("-"))) for value in sorted(values)]
        if len({variant for _, variant in variants}) != len(variants):
            raise ValueError("colliding canonical enum variants: " + property_name)
        output.append(f"/// Canonical typed `{property_name}` values. Provider matches must be exhaustive.\n"
                      f"#[derive(Clone, Copy, Debug, PartialEq, Eq)]\npub enum {name} {{ "
                      + ", ".join(variant for _, variant in variants) + " }")
        output.append(f"impl {name} {{\n"
                      + "pub const ALL: &'static [Self] = &[" + ", ".join("Self::" + variant for _, variant in variants) + "];\n"
                      + "pub fn as_str(self) -> &'static str { match self { "
                      + " ".join(f"Self::{variant} => {quote(value)}," for value, variant in variants) + " } }\n}")
        output.append(f"impl TryFrom<&str> for {name} {{ type Error = String;\n"
                      + "fn try_from(value: &str) -> Result<Self, Self::Error> { match value { "
                      + " ".join(f"{quote(value)} => Ok(Self::{variant})," for value, variant in variants)
                      + f"_ => Err(format!(\"invalid canonical {property_name}: {{value}}\")),"
                      + " } }\n}")
    return "\n\n".join(output)


def compile_validators(schema, contract):
    compiler = Compiler(schema)
    compiler.functions = set(contract["validators"])
    output = ["// Generated from canonical OCaml validators. Do not edit.\nuse super::*;",
              compile_closed_domains(contract.get("closedDomains", {}))]
    for name, expression in contract["validators"].items():
        if name == "node_properties_supported":
            env = {"kind": "&str", "properties": "&Map<String, Value>"}
        elif name == "property_value_supported":
            env = {"property": "&str", "value": "Scalar"}
        elif name == "property_value_supported_for_kind":
            env = {"kind": "&str", "property": "&str", "value": "Scalar"}
        else:
            env = {"value": "f64" if name == "is_finite" else "&str"}
        code, typ = compiler.expr(expression, env)
        if typ != "bool":
            raise ValueError("canonical validator must return bool")
        signature = ", ".join(f"{n}: {t.replace('Scalar', 'Scalar<' + chr(39) + '_>')}" for n, t in env.items())
        output.append(f"pub(super) fn {name}({signature}) -> bool {{ {tail(code)} }}")
    def presence(rule):
        if isinstance(rule, bool):
            return str(rule).lower()
        check = f"contains_property({quote(rule['property'])}, properties)"
        yes, no = presence(rule["yes"]), presence(rule["no"])
        if yes == "true" and no == "false":
            return check
        if yes == "false" and no == "true":
            return "!" + check
        return f"if {check} {{ {yes} }} else {{ {no} }}"

    grouped = {}
    for kind, definition in contract["kinds"].items():
        grouped.setdefault(presence(definition["presence"]), []).append(kind)
    cases = [" | ".join(quote(kind) for kind in kinds) + " => { " + rule + " },"
             for rule, kinds in grouped.items()]
    output.append("pub(super) fn presence_supported(kind: &str, properties: &Map<String, Value>) -> bool { match kind { " + " ".join(cases) + " _ => false, } }")
    return "\n\n".join(output) + "\n"
