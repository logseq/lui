"""Translate the deliberately restricted canonical validation AST into Go.

This compiler accepts a small pure-expression subset, fails on unfamiliar
syntax, and generates predicates rather than maintaining a second rule matrix.
"""
import json

quote = json.dumps


class Compiler:
    def __init__(self, schema):
        self.names = {p["lg"]: p["wire"] for p in schema["properties"]}
        self.names.update({k["lg"]: k["wire"] for k in schema["nodeKinds"]})
        self.counter = 0

    def fresh(self):
        self.counter += 1
        return "contractMatch" + str(self.counter)

    def pattern(self, p, value, typ):
        if "any" in p:
            return "true", {}, []
        if "var" in p:
            return "true", {p["var"]: typ}, [f'{p["var"]} := {value}']
        if "or" in p:
            a, b = p["or"]
            ac, ae, av = self.pattern(a, value, typ)
            bc, be, bv = self.pattern(b, value, typ)
            if ae != be or av != bv:
                raise ValueError("inconsistent bindings in alternative patterns")
            return f"({ac} || {bc})", ae, av
        if "tuple" in p:
            predicates, bindings, declarations = [], {}, []
            for item, (v, t) in zip(p["tuple"], value):
                c, e, d = self.pattern(item, v, t)
                predicates.append(c)
                bindings.update(e)
                declarations += d
            return " && ".join(predicates), bindings, declarations
        if "constructor" in p:
            name = p["constructor"]
            if name == "None":
                return f"!{value}.exists", {}, []
            if name == "Some":
                condition, env, decl = self.pattern(p["argument"], value + ".value", "contractWireValue")
                return f"({value}.exists && ({condition}))", env, decl
            if name in ("StringValue", "IntValue", "FloatValue", "BoolValue"):
                tag, native = {"StringValue": ("scalarString", "string"), "IntValue": ("scalarInt", "float64"),
                               "FloatValue": ("scalarFloat", "float64"), "BoolValue": ("scalarBool", "bool")}[name]
                condition, env, decl = self.pattern(p["argument"], f"{value}.value.({native})", native)
                return f"({value}.kind == {tag} && ({condition}))", env, decl
            name = self.names.get(name, name)
            return f"{value} == {quote(name)}", {}, []
        code, _ = self.expr(p, {})
        return f"{value} == {code}", {}, []

    def expr(self, e, env):
        if "number" in e:
            text = e["number"].replace("_", "")
            if text.endswith("."):
                text += "0"
            return "float64(" + text + ")", "float64"
        if "string" in e:
            return quote(e["string"]), "string"
        if "presence" in e:
            return "contractPresenceSupported(kind, properties)", "bool"
        if "ident" in e:
            name = e["ident"]
            if name in env:
                return name, env[name]
            constants = {"infinity": "math.Inf(1)", "neg_infinity": "math.Inf(-1)", "Float.max_float": "math.MaxFloat64"}
            if name in constants:
                return constants[name], "float64"
            raise ValueError("unknown identifier " + name)
        if "constructor" in e:
            name = e["constructor"]
            if name in ("true", "false"):
                return name, "bool"
            if name == "[]":
                return "[]string{}", "[]string"
            if name == "::":
                head, tail = e["argument"]["tuple"]
                a, _ = self.expr(head, env)
                b, _ = self.expr(tail, env)
                return f"append([]string{{{a}}}, {b}...)", "[]string"
            if name in ("StringValue", "IntValue", "FloatValue", "BoolValue"):
                argument, _ = self.expr(e["argument"], env)
                tag = {"StringValue": "scalarString", "IntValue": "scalarInt", "FloatValue": "scalarFloat", "BoolValue": "scalarBool"}[name]
                return f"contractWireValue{{kind: {tag}, value: {argument}}}", "contractWireValue"
            if name in self.names:
                return quote(self.names[name]), "string"
            raise ValueError("unknown constructor " + name)
        if "tuple" in e:
            return [self.expr(item, env) for item in e["tuple"]], "tuple"
        if "if" in e:
            condition, _ = self.expr(e["if"], env)
            yes, typ = self.expr(e["then"], env)
            no, other = self.expr(e["else"], env)
            if typ != other:
                raise ValueError("inconsistent conditional types")
            return f"func() {typ} {{ if {condition} {{ return {yes} }}; return {no} }}()", typ
        if "let" in e:
            local = dict(env)
            declarations = []
            for binding in e["let"]:
                value, typ = self.expr(binding["value"], local)
                name = binding["pattern"]["var"]
                declarations.append(f"{name} := {value}")
                local[name] = typ
            body, typ = self.expr(e["body"], local)
            return f'func() {typ} {{ {"; ".join(declarations)}; return {body} }}()', typ
        if "match" in e:
            value, typ = self.expr(e["match"], env)
            name = self.fresh()
            if typ == "tuple":
                names = [name + str(i) for i in range(len(value))]
                declaration = ", ".join(names) + " := " + ", ".join(v for v, _ in value)
                pattern_value = [(n, t) for n, (_, t) in zip(names, value)]
            else:
                declaration, pattern_value = f"{name} := {value}", name
            branches, result_type = [], None
            for case in e["cases"]:
                condition, bindings, decl = self.pattern(case["pattern"], pattern_value, typ)
                code, result_type = self.expr(case["value"], {**env, **bindings})
                branches.append(f'if {condition} {{ {"; ".join(decl)}; return {code} }}')
            return f'func() {result_type} {{ {declaration}; {"; ".join(branches)}; panic("unmatched canonical contract") }}()', result_type
        if "call" in e:
            name = e["call"]["ident"]
            args = [self.expr(a, env) for a in e["args"]]
            values = [a for a, _ in args]
            operators = {"=": "==", "<>": "!=", ">=": ">=", "<=": "<=", ">": ">", "<": "<", "+": "+", "&&": "&&", "||": "||"}
            if name in operators:
                return f"({values[0]} {operators[name]} {values[1]})", "float64" if name == "+" else "bool"
            if name == "not":
                return f"!({values[0]})", "bool"
            if name == "Option.is_some":
                return values[0], "bool"
            special = {
                "Property_map.mem": ("contractMem", "bool"), "Property_map.find_opt": ("contractLookup", "contractOptional"),
                "String.trim": ("contractTrim", "string"), "List.mem": ("contractContains", "bool"),
                "true_property": ("contractTrue", "bool"), "treeitem_properties": ("contractTreeItem", "bool"),
                "tree_row_kind": ("contractTreeRow", "bool"), "int_property": ("contractNumber", "float64"),
                "float_property": ("contractNumber", "float64"), "float_property_of": ("contractNumber", "float64"),
                "string_property_or": ("contractString", "string"), "string_property_nonempty": ("contractNonempty", "bool"),
                "surface_size_supported": ("contractSurfaceSize", "bool"), "viewport_size_supported": ("contractViewportSize", "bool"),
                "icon_name_supported": ("contractIcon", "bool"), "anchor_rect_of_string": ("contractAnchorRect", "bool"),
                "data_attrs_value_ok": ("contractDataAttrs", "bool"), "element_tag_known": ("contractKnownTag", "bool"),
                "element_tag_supported": ("contractTag", "bool"), "text_decoration_supported": ("contractTextDecoration", "bool"),
                "transition_supported": ("contractTransition", "bool")}
            target, typ = special.get(name, ("contract_" + name, "bool"))
            return f'{target}({", ".join(values)})', typ
        raise ValueError("unsupported canonical expression " + repr(e))


def compile_validators(schema, contract):
    compiler = Compiler(schema)
    output = []
    for name, expression in contract["validators"].items():
        if name == "node_properties_supported":
            env = {"kind": "string", "properties": "map[string]any"}
        elif name == "property_value_supported":
            env = {"property": "string", "value": "contractWireValue"}
        elif name == "property_value_supported_for_kind":
            env = {"kind": "string", "property": "string", "value": "contractWireValue"}
        else:
            env = {"value": "float64" if name == "is_finite" else "string"}
        code, typ = compiler.expr(expression, env)
        signature = ", ".join(n + " " + t for n, t in env.items())
        output.append(f"func contract_{name}({signature}) {typ} {{ return {code} }}")
    return "\n\n".join(output)
