import ast
import inspect
import pathlib
import unittest

import proxy_core as core


ROOT = pathlib.Path(__file__).resolve().parents[1]
CORE_PATH = ROOT / "proxy_core.py"
THIS_TEST = pathlib.Path(__file__).resolve()

CANONICAL_RUNTIME_OWNERS = {
    "application_filesystem",
    "application_runtime",
    "configuration_storage",
    "local_proxy_transport",
    "logging_bridge",
    "portable_lifecycle",
    "process_supervision",
    "recovery_autostart",
    "routing_policy",
    "system_proxy_runtime",
    "windows_pac_recovery",
    "windows_system_proxy",
}

HISTORICAL_CORE_STDLIB_ALIASES = {
    "base64",
    "hashlib",
    "io",
    "json",
    "os",
    "re",
    "select",
    "socket",
    "struct",
    "subprocess",
    "sys",
    "threading",
    "time",
}

DECOUPLED_OWNER_ATTRIBUTES = {
    "routing_policy.py": {"os", "io", "re"},
    "local_proxy_transport.py": {
        "base64",
        "re",
        "select",
        "socket",
        "struct",
        "threading",
    },
    "process_supervision.py": {
        "io",
        "json",
        "os",
        "socket",
        "subprocess",
        "sys",
    },
    "application_filesystem.py": {"io", "json", "os", "sys"},
    "configuration_storage.py": {
        "base64",
        "hashlib",
        "io",
        "json",
        "os",
        "threading",
        "time",
    },
    "portable_lifecycle.py": {"hashlib", "io", "os", "subprocess", "sys"},
    "application_runtime.py": {"os", "sys"},
    "recovery_autostart.py": {"subprocess", "sys"},
}


def _exact_core_attributes(source: str, module_names=("core",)) -> set[str]:
    tree = ast.parse(source)
    return {
        node.attr
        for node in ast.walk(tree)
        if isinstance(node, ast.Attribute)
        and isinstance(node.value, ast.Name)
        and node.value.id in module_names
    }


def _proxy_core_import_names(tree: ast.AST) -> set[str]:
    names = set()
    for node in ast.walk(tree):
        if not isinstance(node, ast.Import):
            continue
        for imported in node.names:
            if imported.name == "proxy_core":
                names.add(imported.asname or "proxy_core")
    return names


def _historical_alias_consumers() -> dict[str, set[str]]:
    consumers = {name: set() for name in HISTORICAL_CORE_STDLIB_ALIASES}
    for path in ROOT.rglob("*.py"):
        if path.resolve() == THIS_TEST:
            continue
        source = path.read_text(encoding="utf-8-sig")
        tree = ast.parse(source)
        module_names = _proxy_core_import_names(tree)
        if not module_names:
            continue
        used = _exact_core_attributes(source, module_names)
        relative = path.relative_to(ROOT).as_posix()
        for name in used & HISTORICAL_CORE_STDLIB_ALIASES:
            consumers[name].add(relative)
    return {name: paths for name, paths in consumers.items() if paths}


def _plain_imports(path: pathlib.Path) -> set[str]:
    return {
        imported.name
        for node in ast.parse(path.read_text(encoding="utf-8")).body
        if isinstance(node, ast.Import)
        for imported in node.names
    }


def _legacy_module_import_consumers() -> set[str]:
    consumers = set()
    for path in ROOT.rglob("*.py"):
        if path.resolve() == THIS_TEST:
            continue
        tree = ast.parse(path.read_text(encoding="utf-8-sig"))
        for node in ast.walk(tree):
            if isinstance(node, ast.Import) and any(
                imported.name == "proxy_core_legacy" for imported in node.names
            ):
                consumers.add(path.relative_to(ROOT).as_posix())
            if isinstance(node, ast.ImportFrom) and node.module == "proxy_core_legacy":
                consumers.add(path.relative_to(ROOT).as_posix())
    return consumers


class CanonicalCoreCompositionTests(unittest.TestCase):
    def test_proxy_core_is_the_single_canonical_mutable_module_object(self):
        self.assertEqual(core.__name__, "proxy_core")
        self.assertTrue(str(core.__file__).endswith("proxy_core.py"))
        self.assertFalse((ROOT / "proxy_core_legacy.py").exists())
        source = CORE_PATH.read_text(encoding="utf-8")
        self.assertNotIn("import proxy_core_legacy", source)
        self.assertNotIn("_runtime_sys.modules[__name__] =", source)
        self.assertEqual(_legacy_module_import_consumers(), set())

    def test_core_retains_exact_precomposition_state_contract(self):
        expected_version = (ROOT / "VERSION").read_text(encoding="utf-8-sig").strip()
        self.assertEqual(core.APP_VERSION, expected_version)
        self.assertEqual(core.ENGINEERING_MILESTONE, "P0.2")
        self.assertEqual(core._INSTALL_OWNER_MARKER, ".arvectum-install-owner")
        self.assertEqual(core._INSTALL_OWNER_VALUE, "ARVECTUM_PROXY_LAUNCHER_INSTALL_OWNER")
        self.assertIn("ARVECTUM_PROXY_LAUNCHER_WINDOWS_RC2_1", core._LEGACY_INSTALL_OWNER_VALUES)
        self.assertEqual(core._LAUNCHER_EXE_NAME, "Arvectum Proxy Launcher.exe")
        self.assertEqual(core._USER_AUTOSTART_RUN_VALUE, "ArvectumProxyLauncher")
        self.assertIsInstance(core._STATE_READY, bool)
        self.assertIn("proxy_core.log", core._STATE_FILES)

    def test_all_historical_stdlib_aliases_remain_absent_from_core_namespace(self):
        for name in HISTORICAL_CORE_STDLIB_ALIASES:
            self.assertFalse(hasattr(core, name), name)
        self.assertTrue(hasattr(core, "_runtime_sys"))

    def test_historical_aliases_have_no_live_project_consumers(self):
        self.assertEqual(_historical_alias_consumers(), {})

    def test_socket_dependency_is_owned_only_by_canonical_network_modules(self):
        self.assertFalse(hasattr(core, "socket"))
        for relative_path in ("local_proxy_transport.py", "process_supervision.py"):
            path = ROOT / relative_path
            source = path.read_text(encoding="utf-8")
            self.assertIn("socket", _plain_imports(path), relative_path)
            self.assertNotIn("socket", _exact_core_attributes(source), relative_path)

    def test_removed_core_stdlib_names_are_unused_by_all_canonical_owners(self):
        for owner in CANONICAL_RUNTIME_OWNERS:
            source = (ROOT / (owner + ".py")).read_text(encoding="utf-8")
            exact_core_attributes = _exact_core_attributes(source)
            for name in HISTORICAL_CORE_STDLIB_ALIASES:
                self.assertNotIn(name, exact_core_attributes, "%s: core.%s" % (owner, name))

    def test_decoupled_owners_do_not_use_core_as_stdlib_service_locator(self):
        for relative_path, forbidden in DECOUPLED_OWNER_ATTRIBUTES.items():
            source = (ROOT / relative_path).read_text(encoding="utf-8")
            exact_core_attributes = _exact_core_attributes(source)
            for name in forbidden:
                self.assertNotIn(
                    name,
                    exact_core_attributes,
                    "%s: core.%s" % (relative_path, name),
                )

    def test_no_live_runtime_callable_is_implemented_by_composition_root(self):
        core_owned = sorted(
            name
            for name, value in vars(core).items()
            if callable(value) and getattr(value, "__module__", None) == "proxy_core"
        )
        self.assertEqual(core_owned, [])

    def test_every_live_project_runtime_callable_has_an_explicit_canonical_owner(self):
        unexpected = {}
        inventory = {}
        for name, value in vars(core).items():
            if not (inspect.isfunction(value) or inspect.isclass(value)):
                continue
            owner = getattr(value, "__module__", None)
            inventory[name] = owner
            if owner not in CANONICAL_RUNTIME_OWNERS:
                unexpected[name] = owner

        self.assertTrue(inventory)
        self.assertEqual(unexpected, {})

        expected = {
            "install_dir": "application_filesystem",
            "ensure_stable_app_copy": "portable_lifecycle",
            "structured_log": "logging_bridge",
            "load_settings": "configuration_storage",
            "build_pac": "routing_policy",
            "ProxyCore": "local_proxy_transport",
            "is_running": "process_supervision",
            "classify_recovery_autostart": "recovery_autostart",
            "_read_internet_settings": "windows_system_proxy",
            "enable_system_proxy": "system_proxy_runtime",
            "clear_orphaned_arvectum_pac": "windows_pac_recovery",
            "main": "application_runtime",
        }
        for name, owner in expected.items():
            self.assertEqual(inventory.get(name), owner, name)


if __name__ == "__main__":
    unittest.main()
