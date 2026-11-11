"""Exercise fail-closed validator generation and artifact freshness."""
import importlib.util
import json
import shutil
import subprocess
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

TOOLING = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLING))
from nsh_contract_codegen import Compiler, scalar_types, compile_closed_domains

SPEC = importlib.util.spec_from_file_location("generate_nsh_contract", TOOLING / "generate_nsh_contract.py")
GENERATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GENERATOR)


class NSHContractCompilerTest(unittest.TestCase):
    def setUp(self):
        self.compiler = Compiler({"properties": [], "nodeKinds": []})

    def test_unknown_calls_and_syntax_fail_closed(self):
        expressions = [
            {"call": {"ident": "future_validator"}, "args": []},
            {"loop": {"constructor": "true"}},
            {"constructor": "FutureValue"},
            {"ident": "future_constant"},
        ]
        for expression in expressions:
            with self.subTest(expression=expression), self.assertRaises(ValueError):
                self.compiler.expr(expression, {})

    def test_inconsistent_types_and_alternative_bindings_fail_closed(self):
        with self.assertRaisesRegex(ValueError, "type mismatch"):
            self.compiler.expr({"call": {"ident": ">="}, "args": [
                {"number": "1"}, {"string": "1"}]}, {})
        with self.assertRaisesRegex(ValueError, "bindings"):
            self.compiler.pattern({"or": [{"var": "a"}, {"var": "b"}]}, "i64")

    def test_scalar_alternatives_do_not_depend_on_accepted_sample_values(self):
        schema = {"properties": [{"lg": "FutureRange", "wire": "future-range"}], "nodeKinds": []}
        contract = {"validators": {"property_value_supported": {
            "match": {"tuple": [{"ident": "property"}, {"ident": "value"}]},
            "cases": [
                {"pattern": {"tuple": [{"constructor": "FutureRange"},
                    {"constructor": "FloatValue", "argument": {"var": "number"}}]},
                 "value": {"call": {"ident": ">"}, "args": [{"ident": "number"}, {"number": "42."}]}},
                {"pattern": {"any": True}, "value": {"constructor": "false"}},
            ],
        }}}
        self.assertEqual(scalar_types(schema, contract), {"future-range": ["float"]})

    def test_closed_domain_generation_requires_complete_canonical_metadata(self):
        valid = {"display": ["none"], "image-fit": ["fit", "fill"]}
        for name in valid:
            for values in (None, [], ["none", "none"], ["inline_block"], [[]]):
                domains = {**valid, name: values}
                if values is None:
                    del domains[name]
                with self.subTest(property=name, values=values), self.assertRaises(ValueError):
                    compile_closed_domains(domains)

    def test_generated_domains_roundtrip_and_new_cases_break_actual_provider_compilation(self):
        root = TOOLING.parent
        metadata = json.loads((root / "platform/nsh/contract.json").read_text())
        domains = metadata["closedDomains"]
        source = (root / "platform/nsh/src/style.rs").read_text()
        start = source.index("fn display_value(")
        provider = source[start:source.index("\nfn compile_parts(", start)]
        image_source = (root / "platform/nsh/src/images.rs").read_text()
        image_start = image_source.index("fn fit_value(")
        provider += image_source[image_start:image_source.index("\npub(crate) fn fit(", image_start)]
        # Compile the actual provider match, with minimal stand-ins for its
        # external parse types. This proves exhaustiveness, not NSH layout.
        standins = r'''
struct Value(String);
impl Value { fn as_str(&self) -> Option<&str> { Some(&self.0) } }
#[derive(Debug, PartialEq)]
enum ResizeMode { Contain, Cover }
type PropertyValue = String;
enum StyleKey { Display }
enum StyleValue<'a> { Str(&'a str) }
impl StyleKey {
    fn parse_value(self, value: StyleValue<'_>) -> Result<PropertyValue, &'static str> {
        match value {
            StyleValue::Str("none") => Ok("none".into()),
            StyleValue::Str("block") => Ok("block".into()),
            StyleValue::Str(_) => Err("unsupported native display"),
        }
    }
}
'''
        assertions = r'''
fn main() {
    for value in DisplayValue::ALL {
        assert_eq!(DisplayValue::try_from(value.as_str()), Ok(*value));
    }
    for value in ImageFitValue::ALL {
        assert_eq!(ImageFitValue::try_from(value.as_str()), Ok(*value));
    }
    assert_eq!(fit_value(ImageFitValue::Fit), ResizeMode::Contain);
    assert_eq!(fit_value(ImageFitValue::Fill), ResizeMode::Cover);
    assert!(ImageFitValue::try_from("not-canonical").is_err());
    assert!(DisplayValue::try_from("not-canonical").is_err());
    assert_eq!(display_value(&Value("none".into())).unwrap(), "none");
    assert_eq!(display_value(&Value("block".into())).unwrap(), "block");
    for value in ["contents", "inline", "inline-block", "inline-flex"] {
        assert!(display_value(&Value(value.into())).is_err());
    }
}
'''
        rustup = shutil.which("rustup") or str(Path.home() / ".cargo/bin/rustup")
        with tempfile.TemporaryDirectory(prefix="lui-closed-domains-") as directory:
            temporary = Path(directory)
            probe = temporary / "probe.rs"
            binary = temporary / ("probe.exe" if sys.platform == "win32" else "probe")
            def compile_probe(current):
                probe.write_text(compile_closed_domains(current) + standins + provider + assertions)
                return subprocess.run([rustup, "run", "1.97.0", "rustc", "--edition", "2024", "-D", "warnings",
                                       str(probe), "-o", str(binary)], capture_output=True, text=True)
            positive = compile_probe(domains)
            self.assertEqual(positive.returncode, 0, positive.stderr)
            subprocess.run([str(binary)], check=True)
            for property_name in ("display", "image-fit"):
                with self.subTest(property=property_name):
                    expanded = {**domains, property_name: [*domains[property_name], "future-provider-test"]}
                    negative = compile_probe(expanded)
                    self.assertNotEqual(negative.returncode, 0, "a new case bypassed provider exhaustiveness")
                    self.assertIn("E0004", negative.stderr)
                    self.assertIn("FutureProviderTest", negative.stderr)

    def test_freshness_checks_all_artifact_bytes_with_unchanged_source_hashes(self):
        with tempfile.TemporaryDirectory(prefix="lui-contract-freshness-") as directory:
            root = Path(directory)
            (root / "schema").mkdir()
            (root / "schema/components.json").write_text(json.dumps({"properties": [], "nodeKinds": []}))
            outputs = [root / "contract.json", root / "contract_generated.rs", root / "fixtures/oracle.json"]
            exported = {
                "version": 1,
                "closedDomains": {"display": ["none"], "image-fit": ["fit", "fill"]},
                "validators": {
                    "is_finite": {"constructor": "true"},
                    "property_value_supported": {
                        "match": {"tuple": [{"ident": "property"}, {"ident": "value"}]},
                        "cases": [{"pattern": {"any": True}, "value": {"constructor": "false"}}],
                    },
                },
                "kinds": {"text": {"presence": True}},
                "oracle": {"values": []},
            }
            with mock.patch.multiple(GENERATOR, ROOT=root, OUTPUT=outputs[0], VALIDATORS=outputs[1], ORACLE=outputs[2]), \
                    mock.patch.object(GENERATOR, "export_contract", return_value=exported), \
                    mock.patch.object(GENERATOR, "source_hashes", return_value={"canonical.ml": "unchanged"}):
                with mock.patch.object(sys, "argv", ["generate_nsh_contract.py"]):
                    GENERATOR.main()
                with mock.patch.object(sys, "argv", ["generate_nsh_contract.py", "--check"]):
                    GENERATOR.main()
                    for path in outputs:
                        with self.subTest(artifact=path.name):
                            original = path.read_bytes()
                            try:
                                path.write_bytes(original + b" ")
                                with self.assertRaisesRegex(SystemExit, "NSH contract is stale"):
                                    GENERATOR.main()
                            finally:
                                path.write_bytes(original)


if __name__ == "__main__":
    unittest.main()
