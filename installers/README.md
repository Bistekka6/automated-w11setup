# Local Installers Directory

Place any `.exe` or `.msi` application installers in this folder.
When `setup.ps1` runs, it will attempt to install all executables and MSI packages found here silently.

**Note:**
- MSI files are reliably installed silently using standard Windows Installer flags (`/quiet /qn`).
- EXE files require different silent flags depending on the packager. The script passes `/S /quiet /qn` as a best-effort approach. If an installer fails or pops up an interactive window, it means it requires different arguments to install silently.
