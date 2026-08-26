from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
HAS_INSTALLER_TRACK = (
    (ROOT / "installer" / "ArvectumProxyLauncher.iss").is_file()
    and (ROOT / "installer" / "upgrade_helper.ps1").is_file()
)


class ReleaseScriptTests(unittest.TestCase):
    def read(self, name):
        return (ROOT / name).read_text(encoding="utf-8-sig")

    def test_installer_uses_documents_location_and_owner_marker(self):
        text = self.read("install.bat")
        self.assertIn(r"%USERPROFILE%\Documents\ArvectumProxyLauncher", text)
        uninstall = self.read("uninstall.ps1")
        self.assertIn(".arvectum-install-owner", uninstall)
        self.assertIn("ARVECTUM_PROXY_LAUNCHER_INSTALL_OWNER", uninstall)
        self.assertIn("ARVECTUM_PROXY_LAUNCHER_WINDOWS_RC2_1", uninstall)

    def test_owner_marker_migrates_without_breaking_legacy_uninstall(self):
        uninstall = self.read("uninstall.ps1")
        core = self.read("proxy_core.py")
        self.assertIn("ARVECTUM_PROXY_LAUNCHER_INSTALL_OWNER", uninstall)
        self.assertIn("legacyOwnerMarkerValue", uninstall)
        self.assertIn("_LEGACY_INSTALL_OWNER_VALUES", core)

    def test_install_documents_stable_state_locations_are_documented(self):
        text = self.read("INSTALL.txt")
        self.assertIn(r"%USERPROFILE%\Documents\ArvectumProxyLauncher", text)
        self.assertIn(r"%LOCALAPPDATA%\Arvectum\ProxyLauncher", text)

    def test_installer_does_not_unconditionally_delete_same_named_task(self):
        text = self.read("install.bat")
        self.assertIn('install.ps1', text)
        self.assertNotIn('schtasks /Delete', text)

    def test_python_fallback_installs_powershell_uninstaller(self):
        text = self.read("install.bat")
        self.assertIn("install.ps1", text)

    def test_exe_installer_copies_install_instructions_and_requires_marker(self):
        text = self.read("install.bat")
        self.assertIn('-SourceDir "%~dp0"', text)
        self.assertIn('install.ps1" -AppDir', text)
        uninstall = self.read("uninstall.ps1")
        self.assertIn('if ($Install)', uninstall)
        self.assertIn('Installer finalization failed', uninstall)
        self.assertIn("'INSTALL.txt'", uninstall)
        self.assertIn("'uninstall.ps1'", uninstall)
        self.assertIn("'install.ps1'", uninstall)

    def test_p03_installer_stages_verifies_and_atomically_replaces_exe(self):
        text = self.read("uninstall.ps1")
        self.assertIn("$stagedExe = $exeForInstall + '.new'", text)
        self.assertIn("$oldExe = $exeForInstall + '.old'", text)
        self.assertIn("source EXE hash", text)
        self.assertIn("staged EXE hash", text)
        self.assertIn("final installed EXE hash", text)
        self.assertIn("Move-Item -LiteralPath $exeForInstall -Destination $oldExe", text)
        self.assertIn("previous Launcher was restored", text)

    def test_p03_installer_closes_only_exact_owned_gui_and_verifies_shortcut(self):
        text = self.read("uninstall.ps1")
        self.assertIn("function Close-OwnedLauncher", text)
        self.assertIn("Get-CimInstance Win32_Process", text)
        self.assertIn("Test-ExactPath $_.ExecutablePath $path", text)
        self.assertIn("Test-FileUnlocked", text)
        self.assertIn("desktop shortcut verification failed", text)

    def test_p03_installer_migrates_only_proven_legacy_run_values(self):
        text = self.read("uninstall.ps1")
        self.assertIn("function Test-LegacyArvectumCommand", text)
        self.assertIn("arvectum-proxy-launcher-windows", text)
        self.assertIn("legacy recovery Run value removed", text)
        self.assertIn("legacy user autostart migrated", text)
        self.assertNotIn("taskkill /IM", text)

    def test_p04_installer_stops_only_proven_active_legacy_recovery(self):
        text = self.read("uninstall.ps1")
        self.assertIn("function Get-RecoveryRunClassification", text)
        self.assertIn("function Get-LegacyOwnedProcesses", text)
        self.assertIn("function Stop-LegacyRecoveryProcess", text)
        self.assertIn("legacy recovery --stop result", text)
        self.assertIn("legacy Arvectum recovery process did not exit", text)
        self.assertIn("active legacy Arvectum recovery process cannot be safely stopped", text)
        self.assertIn("Test-ExactPath $_.ExecutablePath $parsed.path", text)
        self.assertNotIn('taskkill /IM "Arvectum Proxy Launcher.exe" /F', text)

    def test_p04_legacy_temp_zip_patterns_and_stale_cleanup_are_strict(self):
        text = self.read("uninstall.ps1")
        self.assertIn("arvectum-proxy-launcher-windows-(?:rc2", text)
        self.assertIn("STALE_LEGACY_ARVECTUM", text)
        self.assertIn("stale legacy Arvectum recovery autostart removed", text)
        self.assertIn("FOREIGN_OR_UNKNOWN", text)
        self.assertIn("conflicting recovery autostart is not owned by Arvectum", text)

    def test_p04_checks_legacy_recovery_before_generic_backup_block(self):
        text = self.read("uninstall.ps1")
        migration = text.index("Migrate-LegacyRunValues $exeForInstall")
        backup_block = text.index("recovery backups remain after stopping the previous version")
        self.assertLess(migration, backup_block)
        self.assertIn("Test-LegacyRecoveryBackupsRemain", text)

    def test_p04_interactive_installer_uses_utf8_and_keeps_failure_visible(self):
        text = self.read("install.bat")
        self.assertIn("chcp 65001 >nul", text)
        self.assertIn("install.ps1", text)
        wrapper = self.read("install.ps1")
        self.assertIn("Installation did not complete", wrapper)
        self.assertIn("Reason:", wrapper)
        self.assertIn("install.log", wrapper)

    def test_p04_release_note_is_required_by_installer(self):
        text = self.read("uninstall.ps1")
        self.assertIn("RELEASE_NOTES_0.2.2_P0.4.md", text)

    def test_interactive_install_keeps_console_open_with_diagnostic(self):
        text = self.read("install.bat")
        wrapper = self.read("install.ps1")
        self.assertIn("Installation did not complete", wrapper)
        self.assertIn("install.log", wrapper)
        self.assertIn("if not defined ARVECTUM_NONINTERACTIVE pause", text)

    def test_uninstaller_requires_owner_marker_before_recursive_remove(self):
        text = self.read("uninstall.ps1")
        marker_pos = text.index("ownership marker is missing")
        remove_pos = text.index("Remove-Item -LiteralPath $fullAppDir -Recurse -Force")
        self.assertLess(marker_pos, remove_pos)
        self.assertIn("ReparsePoint", text)
        self.assertIn("unexpected application directory", text)

    def test_uninstaller_keeps_rollback_before_recursive_remove(self):
        text = self.read("uninstall.ps1")
        rollback_pos = text.index("& $exe --rollback")
        remove_pos = text.index("Remove-Item -LiteralPath $fullAppDir -Recurse -Force")
        self.assertLess(rollback_pos, remove_pos)
        self.assertIn("Network restore is incomplete", text)

    def test_uninstaller_closes_only_processes_owned_by_exact_exe_path(self):
        text = self.read("uninstall.ps1")
        self.assertIn("Name='Arvectum Proxy Launcher.exe'", text)
        self.assertIn("GetFullPath($_.ExecutablePath) -ieq $exe", text)
        self.assertIn("Stop-Process -Id $process.ProcessId", text)

    def test_source_helper_bats_target_documents_install(self):
        for name in ("run_gui.bat", "start_proxy.bat", "stop_proxy.bat"):
            text = self.read(name)
            self.assertIn(r"%USERPROFILE%\Documents\ArvectumProxyLauncher", text)
            self.assertNotIn(r"%LOCALAPPDATA%\ArvectumProxyLauncher", text)

    def test_restore_helper_targets_documents_install(self):
        text = self.read("restore_network.bat")
        self.assertIn(r"%USERPROFILE%\Documents\ArvectumProxyLauncher", text)

    def test_release_version_is_visible_in_gui(self):
        product_version = self.read("VERSION").strip()
        core_text = self.read("proxy_core.py")
        gui_text = self.read("proxy_gui.py")
        self.assertIn(f'APP_VERSION = "{product_version}"', core_text)
        self.assertIn('ENGINEERING_MILESTONE = "P0.2"', core_text)
        self.assertIn('APP_VERSION = core.APP_VERSION', gui_text)
        self.assertIn('ARVECTUM · %s · arvectum.com', gui_text)

    def test_default_connection_check_uses_arvectum_site(self):
        gui_text = self.read("proxy_gui.py")
        self.assertIn('tk.StringVar(value="https://arvectum.com")', gui_text)

    def test_windows_version_resource_is_required(self):
        build = self.read("tools/clean_build_windows.ps1")
        version = self.read("version_info.txt")
        product_version = self.read("VERSION").strip()
        major, minor, patch = product_version.split("-")[0].split(".")
        file_version = f"{major}.{minor}.{patch}.0"
        self.assertIn('--version-file "version_info.txt"', build)
        for value in ('ООО «Арвектум»', 'Arvectum Proxy Launcher', product_version, file_version):
            self.assertIn(value, version)

    @unittest.skipUnless(HAS_INSTALLER_TRACK, "installer track is not present in portable P0 branch")
    def test_inno_setup_is_self_contained_and_hash_verifies_payload(self):
        text = self.read("installer/ArvectumProxyLauncher.iss")
        self.assertIn("Uninstallable=yes", text)
        self.assertIn("ExtractTemporaryFile", text)
        self.assertIn("upgrade_helper.ps1", text)
        self.assertIn("build_manifest.json", text)
        self.assertIn("InstallFailure", text)
        self.assertNotIn("SourceDir", text)
        self.assertNotIn("skipifsourcedoesntexist", text)
        helper = self.read("installer/upgrade_helper.ps1")
        self.assertIn("application_sha256", helper)
        self.assertIn("upgrade_helper_sha256", helper)

    @unittest.skipUnless(HAS_INSTALLER_TRACK, "installer track is not present in portable P0 branch")
    def test_upgrade_helper_has_preflight_transaction_and_session_logging(self):
        text = self.read("installer/upgrade_helper.ps1")
        self.assertIn("=== INSTALL SESSION START", text)
        self.assertIn("=== INSTALL SESSION END: PASS", text)
        self.assertIn("ERROR TYPE:", text)
        self.assertIn("ERROR MESSAGE:", text)
        self.assertIn("embedded application expected SHA256", text)
        self.assertIn("transactional replacement rolled back", text)
        self.assertIn("conflicting recovery autostart is not owned", text)
        self.assertIn("releaseFolder", text)
        self.assertIn("arvectum-proxy-launcher-windows", text)
        self.assertNotIn("& (Join-Path $SourceDir", text)

    @unittest.skipUnless(HAS_INSTALLER_TRACK, "installer track is not present in portable P0 branch")
    def test_inno_uninstall_uses_installed_rollback_helper(self):
        text = self.read("installer/ArvectumProxyLauncher.iss")
        helper = self.read("installer/uninstall_helper.ps1")
        self.assertIn("RunInstalledUninstallHelper", text)
        self.assertIn("InitializeUninstall(): Boolean", text)
        self.assertIn("{app}\\uninstall_helper.ps1", text)
        self.assertNotIn("RunEmbeddedHelper('uninstall_helper.ps1'", text)
        self.assertNotIn("ExtractTemporaryFile('uninstall_helper.ps1')", text)
        self.assertIn("Network rollback", helper)
        self.assertIn("Start-Process", helper)
        self.assertIn("-PassThru", helper)
        self.assertIn("-Wait", helper)
        self.assertIn("$rollback.ExitCode", helper)

    @unittest.skipUnless(HAS_INSTALLER_TRACK, "installer track is not present in portable P0 branch")
    def test_inno_uninstall_deletes_only_exact_owned_payload_files(self):
        text = self.read("installer/ArvectumProxyLauncher.iss")
        self.assertIn("[UninstallDelete]", text)
        for name in ("Arvectum Proxy Launcher.exe", "Arvectum Proxy Launcher.exe.new", "Arvectum Proxy Launcher.exe.old", ".arvectum-install-owner"):
            self.assertIn('Name: "{app}\\' + name + '"', text)

    @unittest.skipUnless(HAS_INSTALLER_TRACK, "installer track is not present in portable P0 branch")
    def test_verified_payload_placement_is_in_primary_files_phase(self):
        text = self.read("installer/ArvectumProxyLauncher.iss")
        self.assertIn("AfterInstall: InstallVerifiedPayload", text)
        install = text[text.index("procedure InstallVerifiedPayload"):text.index("procedure CurStepChanged")]
        post_install = text[text.index("procedure CurStepChanged"):]
        self.assertIn("RunEmbeddedHelper('upgrade_helper.ps1'", install)
        self.assertIn("RaiseException(ErrorText)", install)
        self.assertNotIn("RunEmbeddedHelper('upgrade_helper.ps1'", post_install)

    def test_installer_workflow_waits_for_gui_processes(self):
        text = self.read(".github/workflows/windows-installer.yml")
        self.assertIn("Start-Process", text)
        self.assertIn("-PassThru -Wait", text)
        self.assertIn("$p.ExitCode", text)
        self.assertNotIn("& $setup", text)
        self.assertNotIn("& $exe --status", text)
        self.assertNotIn("& $uninstaller", text)

    @unittest.skipUnless(HAS_INSTALLER_TRACK, "installer track is not present in portable P0 branch")
    def test_upgrade_helper_hashing_is_independent_of_get_filehash_cmdlet(self):
        text = self.read("installer/upgrade_helper.ps1")
        self.assertIn("System.Security.Cryptography.SHA256", text)
        self.assertNotIn("Get-FileHash", text)

    @unittest.skipUnless(HAS_INSTALLER_TRACK, "installer track is not present in portable P0 branch")
    def test_upgrade_helper_waits_for_gui_rollback_under_strict_mode(self):
        text = self.read("installer/upgrade_helper.ps1")
        rollback = text[text.index("function Invoke-PreviousRollback"):text.index("try {\n  Write-InstallLog")]
        self.assertIn("Start-Process -FilePath $ExistingExe -ArgumentList '--stop' -Wait -PassThru", rollback)
        self.assertIn("$rollback.ExitCode", rollback)
        self.assertNotIn("$global:LASTEXITCODE", rollback)
        self.assertNotIn("& $ExistingExe --stop", rollback)

    @unittest.skipUnless(HAS_INSTALLER_TRACK, "installer track is not present in portable P0 branch")
    def test_uninstall_helper_waits_for_gui_rollback_under_strict_mode(self):
        text = self.read("installer/uninstall_helper.ps1")
        self.assertIn("Start-Process", text)
        self.assertIn("-PassThru", text)
        self.assertIn("-Wait", text)
        self.assertIn("$rollback.ExitCode", text)
        self.assertNotIn("& $exe --rollback", text)

    def test_uninstaller_removes_own_installed_apps_entry_and_start_menu_shortcut(self):
        text = self.read("uninstall.ps1")
        self.assertIn("ArvectumProxyLauncher'", text)
        self.assertIn("$startMenuShortcut", text)
        self.assertIn("Remove-Item -LiteralPath $arpKey", text)

    def test_gui_autostart_uses_owned_per_user_run_value(self):
        text = self.read("proxy_gui.py")
        self.assertIn("AUTOSTART_RUN_VALUE", text)
        self.assertIn("AUTOSTART_RUN_PATH", text)
        self.assertIn("_autostart_run_is_ours", text)
        self.assertIn("winreg.SetValueEx", text)
        self.assertIn("_autostart_task_is_ours", text)
        self.assertIn("принадлежит другой команде", text)

    def test_portable_fallback_does_not_repair_run_to_unconfirmed_canonical(self):
        text = self.read("proxy_gui.py")
        self.assertIn("portable_fallback = _portable_fallback_active()", text)
        self.assertIn("canonical execution was not confirmed", text)
        self.assertIn("core.repair_portable_run_entries()", text)
        self.assertIn("Автозапуск временно отключён", text)

    def test_recovery_run_value_is_ownership_checked(self):
        text = self.read("proxy_core.py")
        self.assertIn("LEGACY_ARVECTUM", text)
        self.assertIn("conflicts with a foreign command", text)
        self.assertIn("leaving it untouched", text)
        self.assertIn("classify_recovery_autostart", text)

    def test_gui_contains_explicit_recovery_guidance(self):
        text = self.read("proxy_gui.py")
        self.assertIn("Предыдущий сеанс proxy завершился некорректно", text)
        self.assertIn("Восстановить настройки сети", text)
        self.assertIn('self.btn_restore.configure(style="Mint.TButton")', text)
        self.assertIn("Сеть восстановлена. Теперь можно снова включить прокси.", text)

    def test_gui_has_targeted_orphan_pac_action(self):
        text = self.read("proxy_gui.py")
        self.assertIn("ОБНАРУЖЕН СТАРЫЙ PAC ARVECTUM", text)
        self.assertIn("Удалить старый PAC и продолжить", text)
        self.assertIn("clear_orphaned_arvectum_pac", text)
        self.assertIn("Остальные настройки Windows не изменялись", text)

    def test_main_header_is_text_based_and_has_no_banner_or_separator(self):
        text = self.read("proxy_gui.py")
        launcher = text[text.index("class Launcher:"):]
        self.assertIn('text=APP_NAME, bg=NAVY, fg=MINT', launcher)
        self.assertIn('font=B["font_brand"]', launcher)
        self.assertNotIn('_load_photo("arvectum-banner.png"', launcher)
        self.assertNotIn('tk.Frame(root, bg=MINT, height=3)', launcher)

    def test_main_controls_have_clear_visual_hierarchy(self):
        text = self.read("proxy_gui.py")
        self.assertIn('style.configure("Navy.TButton"', text)
        self.assertIn('text="Проверить соединение"', text)
        self.assertIn('text="Настройки и сервис"', text)
        self.assertIn('text="Состояние"', text)


if __name__ == "__main__":
    unittest.main()