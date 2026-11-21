# update-system
 
A one-command full update for Arch Linux gaming setups. It updates repo, AUR and Flatpak packages together and checks for the problems that tend to break games after an update.
 
## Why
 
On Arch, the system updates fine but games break afterwards in ways that are hard to trace:
 
- **Flatpak apps fall back to software rendering** after an NVIDIA driver update. Flatpaks don't use the host driver. They need a matching `GL`/`GL32` NVIDIA runtime at the exact same version, and nothing warns you when it's missing.
- **Out-of-tree kernel modules disappear** after a kernel update. Non-DKMS AUR packages build modules for one kernel version only, so the device (for example a controller) silently stops working.
- **Manual interventions** announced in the Arch news get missed.
- **`.pacnew` files** pile up unnoticed.
This script handles all of that in a single run.
 
## What it does
 
| Step | Description |
|------|-------------|
| 0 | Checks that out-of-tree kernel modules exist for the running kernel and rebuilds their packages if they don't |
| 1 | Shows unread Arch Linux news and asks whether to continue |
| 2 | Creates a Timeshift snapshot before any changes |
| 3 | Updates repo and AUR packages (`paru -Syu` or `yay -Syu`) |
| 4 | Updates Flatpak apps and runtimes |
| 5 | Verifies Flatpak has the NVIDIA `GL` and `GL32` runtimes matching the system driver, and installs them if missing |
| 6 | Lists `.pacnew` files that need merging |
| 7 | Summarises kernel and GPU package changes and tells you when to reboot and rebuild modules |
 
## Requirements
 
- Arch Linux (or an Arch-based distro)
- An AUR helper: [`paru`](https://github.com/Morganamilo/paru) (preferred) or [`yay`](https://github.com/Jguer/yay). The script detects which one is installed and uses it for AUR updates, news and module rebuilds. Without either, it falls back to `pacman` for repo updates only.
- `flatpak`
- [`timeshift`](https://github.com/linuxmint/timeshift) *(optional)*. Use btrfs mode for fast snapshots.
- `pacman-contrib` *(optional)*, which provides `pacdiff` for merging `.pacnew` files
## Installation
 
```bash
git clone https://github.com/<your-user>/update-system.git
cd update-system
install -Dm755 update-system.sh ~/.local/bin/update-system
```
 
Make sure `~/.local/bin` is in your `PATH`:
 
```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc   # or ~/.zshrc
```
 
## Usage
 
```bash
update-system            # full update
update-system --modules  # only check and rebuild out-of-tree kernel modules
```
 
### After a kernel update
 
Out-of-tree module packages build against the **running** kernel, so they can't be rebuilt correctly until you've rebooted into the new one. The script tells you when this applies:
 
```
! Kernel changed — after rebooting, run: update-system --modules
```
 
Running a full `update-system` after the reboot also works, because step 0 runs the module check first.
 
## Configuration
 
Edit the variables at the top of the script.
 
### `WATCH_PKGS`
 
Packages whose changes trigger the reboot reminder:
 
```bash
WATCH_PKGS="linux linux-lts nvidia-open-dkms nvidia-utils lib32-nvidia-utils mesa lib32-mesa linux-firmware"
```
 
### `MODULE_PKGS`
 
Non-DKMS packages that ship kernel modules, written as `package:module`. The script checks that each module exists for the running kernel and rebuilds the package if it doesn't:
 
```bash
MODULE_PKGS=("linux-switch2:hid-switch2")
```
 
To find the module name for a package, run:
 
```bash
pacman -Ql <package> | grep '\.ko'
```
 
DKMS packages (such as `nvidia-open-dkms`) don't need to be listed here, because DKMS rebuilds them automatically for every installed kernel.
 
## Limitations
 
- **Non-DKMS modules exist for one kernel at a time.** If you boot a fallback kernel (for example LTS), the module is missing there until you run `update-system --modules` on that kernel, which then removes it from the other one. Switching the package to DKMS is the proper long-term fix.
- **The NVIDIA Flatpak check assumes `nvidia-utils`.** Systems without NVIDIA skip this step.
- **Timeshift snapshots need root**, so you'll be asked for your `sudo` password.
## License
 
MIT
 
