"""Exercise fail-closed validator generation and artifact freshness."""
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

TOOLING = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLING))
from nsh_contract_codegen import Compiler, scalar_types

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

    def test_freshness_checks_all_artifact_bytes_with_unchanged_source_hashes(self):
        with tempfile.TemporaryDirectory(prefix="lui-contract-freshness-") as directory:
            root = Path(directory)
            (root / "schema").mkdir()
            (root / "schema/components.json").write_text(json.dumps({"properties": [], "nodeKinds": []}))
            outputs = [root / "contract.json", root / "contract_generated.rs", root / "fixtures/oracle.json"]
            exported = {
                "version": 1,
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
