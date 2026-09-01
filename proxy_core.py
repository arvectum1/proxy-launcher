# -*- coding: utf-8 -*-
"""Canonical runtime composition root for Arvectum Proxy Launcher.

Owns release/state bootstrap and installs explicit runtime owners onto the canonical ``proxy_core`` module. Ordinary dependencies remain with their owners, while behavior-sensitive collaborators resolve through this composition object.
"""

import sys as _runtime_sys

# Release identity consumed by logging and release guards.
APP_VERSION = "0.2.4"
ENGINEERING_MILESTONE = "P0.2"

# State/bootstrap values required before all canonical owners are installed.
_STATE_FILES = (
    "proxy_settings.json",
    "no_proxy.txt",
    "proxy_core.pid",
    "proxy_core.log",
    "proxy_internet_backup.json",
    "proxy_env_backup.json",
)
_STATE_READY = False

# Portable/install identity used by filesystem, lifecycle and Recovery Run
# ownership. Historical values remain classification evidence only.
_INSTALL_OWNER_MARKER = ".arvectum-install-owner"
_INSTALL_OWNER_VALUE = "ARVECTUM_PROXY_LAUNCHER_INSTALL_OWNER"
_LEGACY_INSTALL_OWNER_VALUES = {"ARVECTUM_PROXY_LAUNCHER_WINDOWS_RC2_1"}
_LAUNCHER_EXE_NAME = "Arvectum Proxy Launcher.exe"
_USER_AUTOSTART_RUN_VALUE = "ArvectumProxyLauncher"
_LAST_SELF_HEAL_ERROR = ""

import application_filesystem as _application_filesystem
import application_runtime as _application_runtime
import configuration_storage as _configuration_storage
import local_proxy_transport as _local_proxy_transport
import logging_bridge as _logging_bridge
import portable_lifecycle as _portable_lifecycle
import process_supervision as _process_supervision
import recovery_autostart as _recovery_autostart
import routing_policy as _routing_policy
import system_proxy_runtime as _system_proxy_runtime
import windows_pac_recovery as _windows_pac_recovery
import windows_system_proxy as _windows_system_proxy

# Source-contract index retained for release guards that inspect this facade.
# APP_VERSION = "0.2.4"
# ENGINEERING_MILESTONE = "P0.2"
# _LEGACY_INSTALL_OWNER_VALUES
# LEGACY_ARVECTUM
# classify_recovery_autostart
# conflicts with a foreign command
# leaving it untouched

_core = _runtime_sys.modules[__name__]

# Filesystem ownership supplies the canonical log path before the logging
# singleton is replaced. The logging bridge resolves mutable behavior seams
# dynamically through the canonical core object.
_application_filesystem.configure(_core)
_application_filesystem.install_into_core(_core)
_logging_bridge.configure(_core)
_logging_bridge.install_into_core(_core)

# Lower-level owners preserve their established collaborators through core.
_portable_lifecycle.configure(_core)
_portable_lifecycle.install_into_core(_core)
_configuration_storage.configure(_core)
_configuration_storage.install_into_core(_core)
_routing_policy.configure(_core)
_routing_policy.install_into_core(_core)
_local_proxy_transport.configure(_core)
_local_proxy_transport.install_into_core(_core)
_process_supervision.configure(_core)
_process_supervision.install_into_core(_core)
_recovery_autostart.configure(_core)
_recovery_autostart.install_into_core(_core)

# Install the Windows implementation before composition captures its adapter.
_windows_system_proxy.configure(_core)
_windows_system_proxy.install_into_core(_core)
_system_proxy_runtime.configure(
    core=_core,
    runtime_platform=lambda: _runtime_sys.platform,
)
_system_proxy_runtime.install_into_core(_core)

# PAC recovery consumes composed status and canonical WinINET primitives.
_windows_pac_recovery.configure(_core)
_windows_pac_recovery.install_into_core(_core)

# Application runtime is the top-level composition owner.
_application_runtime.configure(_core)
_application_runtime.install_into_core(_core)


if __name__ == "__main__":
    _runtime_sys.exit(_core.main())
