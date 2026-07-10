# GPU (CUDA) Acceleration for PixInsight on Kubuntu

Enable NVIDIA GPU acceleration for **PixInsight** and the **RC Astro** tools
(StarXTerminator, NoiseXTerminator, BlurXTerminator) on **Kubuntu / Ubuntu
24.04 LTS or 26.04 LTS**.

On a typical machine this takes StarXTerminator from ~40 s (CPU) down to ~14 s
(GPU), and PixInsight runs faster overall than on Windows 11.

> Kubuntu is Ubuntu with the KDE Plasma desktop (a Windows-like environment)
> and is what PixInsight recommends. These instructions work on plain Ubuntu too.

---

## TL;DR — automated install

Everything below (except downloading Kubuntu itself) is automated by
[`setup-cuda-pixinsight.sh`](./setup-cuda-pixinsight.sh):

```bash
git clone https://github.com/joeytroy/pixinsight-linux-cuda.git
cd pixinsight-linux-cuda
chmod +x setup-cuda-pixinsight.sh
./setup-cuda-pixinsight.sh
```

The script is **resumable**. It installs the NVIDIA driver, stops for the one
required reboot, and then continues from where it left off when you run it
again. Two downloads are behind logins and **cannot be automated** — the script
pauses with instructions when it needs them (see
[Two files you must download yourself](#two-files-you-must-download-yourself)).

| Command | What it does |
|---|---|
| `./setup-cuda-pixinsight.sh` | Run or resume the full install |
| `./setup-cuda-pixinsight.sh --status` | Show which steps are complete |
| `./setup-cuda-pixinsight.sh --verify` | Check the GPU/CUDA/TF stack is healthy |
| `./setup-cuda-pixinsight.sh --repair-driver` | Purge & reinstall the NVIDIA driver |
| `./setup-cuda-pixinsight.sh --reset` | Forget saved progress and start over |
| `./setup-cuda-pixinsight.sh --help` | Show usage |

> Run the script as your **normal user**, not with `sudo`. It calls `sudo`
> itself where needed and edits your own `~/.bashrc`.

---

## The software stack

These specific versions are known to work together:

| Component | Version | Notes |
|---|---|---|
| NVIDIA driver | recommended by `ubuntu-drivers` | e.g. 570/595 (open) |
| CUDA toolkit | **12.8** | installs to `/usr/local/cuda-12.8` |
| cuDNN | **8.9.7** | Ubuntu 22.04 debs, compatible with 24.04/26.04 |
| TensorFlow C libs | **2.15.0** | matches CUDA 12.x; replaces PixInsight's bundled TF |
| PixInsight | latest Linux build | 1.9.4+ |

> `nvidia-smi` reports the **maximum** CUDA version the driver supports (e.g.
> 13.x) — that does **not** mean 13.x is installed. We deliberately install the
> **12.8** toolkit because that's what TensorFlow 2.15.0 needs.

---

## Prerequisites — install Kubuntu (not automated)

1. Get a USB stick (16 GB+ is plenty).
2. Download the Kubuntu **26.04 LTS** ISO from <https://kubuntu.org> (24.04 LTS
   also works).
3. Flash it with [Rufus](https://rufus.ie/downloads/): select your USB stick and
   the ISO, change the partition scheme to **GPT**. When Rufus says it's a
   hybrid ISO and will use **DD mode**, that's fine.
4. Reboot, enter your BIOS, set the USB stick first in the boot order, and boot
   from it.
5. Choose **Install Kubuntu → Normal installation**. **Do not** tick "install
   third-party software for graphics" — the driver is installed later by the
   script.
6. If dual-booting, choose **Install alongside Windows** and drag the divider to
   size the Kubuntu partition. A GRUB menu will let you pick Kubuntu or Windows
   at boot.
   - Filesystem: `ext4` is the safe default. `btrfs` additionally lets you take
     rollback **snapshots** (install [Timeshift](https://github.com/linuxmint/timeshift))
     and optionally enable compression. Snapshots are not full backups.
   - If the machine boots straight into Windows afterward, fix the boot order in
     your BIOS (Kubuntu first).

Once you've booted into Kubuntu, open **Konsole** (the terminal) and run the
script above — or follow the manual steps below.

---

## Two files you must download yourself

Both are behind account logins, so the script can't fetch them. Save them to
`~/Downloads` (the script auto-detects them there) or pass their paths via
environment variables.

### 1. cuDNN 8.9.7 (NVIDIA Developer login + 2FA)

1. Join / sign in to the NVIDIA Developer Program: <https://developer.nvidia.com/cudnn>
   (you'll set up an authenticator app such as Google Authenticator for 2FA).
2. Open the archive: <https://developer.nvidia.com/rdp/cudnn-archive>
3. Pick **"Download cuDNN v8.9.7 (December 5th, 2023) for CUDA 12.x"**.
4. Pick **"Local Installer for Ubuntu22.04 x86_64 (Deb)"** →
   `cudnn-local-repo-ubuntu2204-8.9.7.29_1.0-1_amd64.deb`.
5. Save it into `~/Downloads`.

```bash
# or point the script at it explicitly:
CUDNN_DEB=~/Downloads/cudnn-local-repo-ubuntu2204-8.9.7.29_1.0-1_amd64.deb \
  ./setup-cuda-pixinsight.sh
```

### 2. PixInsight for Linux (licensed account)

1. Go to <https://pixinsight.com/downloads/index.html> → **Software
   Distribution** → **Linux**.
2. Download the tarball, e.g. `PI-linux-x64-1.9.4-YYYYMMDD-c.tar.xz`.
3. Save it into `~/Downloads`.

```bash
PIXINSIGHT_TARBALL=~/Downloads/PI-linux-x64-1.9.4-20260522-c.tar.xz \
  ./setup-cuda-pixinsight.sh
```

---

## What the script does (manual equivalent)

If you'd rather do it by hand, these are the exact steps the script performs.

<details>
<summary><b>1. Update the system</b></summary>

```bash
sudo apt update && sudo apt upgrade
```

</details>

<details>
<summary><b>2. Install the GCC toolchain</b></summary>

```bash
sudo apt install build-essential
```

</details>

<details>
<summary><b>3. Install the NVIDIA driver (then reboot)</b></summary>

```bash
sudo ubuntu-drivers install
sudo reboot
# after reboot, confirm the driver loaded:
nvidia-smi
```

</details>

<details>
<summary><b>4. Install the CUDA 12.8 toolkit</b></summary>

```bash
cd ~/Downloads
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-ubuntu2404.pin
sudo mv cuda-ubuntu2404.pin /etc/apt/preferences.d/cuda-repository-pin-600
wget https://developer.download.nvidia.com/compute/cuda/12.8.1/local_installers/cuda-repo-ubuntu2404-12-8-local_12.8.1-570.124.06-1_amd64.deb
sudo dpkg -i cuda-repo-ubuntu2404-12-8-local_12.8.1-570.124.06-1_amd64.deb
sudo cp /var/cuda-repo-ubuntu2404-12-8-local/cuda-*-keyring.gpg /usr/share/keyrings/
sudo apt-get update
sudo apt-get -y install cuda-toolkit-12-8
```

Installs to `/usr/local/cuda-12.8` (symlinked as `/usr/local/cuda`).
</details>

<details>
<summary><b>5. Configure the environment</b></summary>

Add to the end of `~/.bashrc`:

```bash
export PATH="/usr/local/cuda/bin:$PATH"
export LD_LIBRARY_PATH="/usr/local/cuda/lib64:$LD_LIBRARY_PATH"
export TF_FORCE_GPU_ALLOW_GROWTH="true"
```

Then:

```bash
source ~/.bashrc
echo "/usr/local/cuda/lib64" | sudo tee -a /etc/ld.so.conf
sudo ldconfig
```

</details>

<details>
<summary><b>6. Install cuDNN 8.9.7</b> (needs the downloaded .deb)</summary>

```bash
cd ~/Downloads
mkdir -p cudnn_install && cp cudnn-local-repo-ubuntu2204-8.9.7.29_1.0-1_amd64.deb cudnn_install/cudnn.deb
cd cudnn_install
ar -x cudnn.deb
tar -xf data.tar.xz
cd var/cudnn-local-repo-ubuntu2204-8.9.7.29/
sudo dpkg -i libcudnn8_8.9.7.29-1+cuda12.2_amd64.deb
sudo dpkg -i libcudnn8-dev_8.9.7.29-1+cuda12.2_amd64.deb
sudo dpkg -i libcudnn8-samples_8.9.7.29-1+cuda12.2_amd64.deb
sudo ldconfig
```

Installs to `/usr/lib/x86_64-linux-gnu/`.
</details>

<details>
<summary><b>7. Install TensorFlow 2.15.0 C libraries</b></summary>

```bash
cd ~/Downloads
wget https://storage.googleapis.com/tensorflow/libtensorflow/libtensorflow-gpu-linux-x86_64-2.15.0.tar.gz
sudo tar -C /usr/local -xzf libtensorflow-gpu-linux-x86_64-2.15.0.tar.gz
sudo ldconfig /usr/local/lib
```

Installs to `/usr/local/lib`.
</details>

<details>
<summary><b>8. Install PixInsight</b> (needs the downloaded tarball)</summary>

```bash
cd ~/Downloads
tar -xf PI-linux-x64-1.9.4-20260522-c.tar.xz
sudo ./installer
```

</details>

<details>
<summary><b>9. Point PixInsight at the CUDA-enabled TensorFlow</b></summary>

PixInsight ships its own TensorFlow. Remove it so PixInsight falls back to the
CUDA-enabled `2.15.0` libraries in `/usr/local/lib`:

```bash
sudo rm /opt/PixInsight/bin/lib/libtensorflow*
```

`TF_FORCE_GPU_ALLOW_GROWTH="true"` was already added in step 5.
</details>

Start PixInsight from a **new terminal**, install the RC Astro tools, and run a
process (e.g. StarXTerminator) to confirm the speed-up.

---

## Upgrading PixInsight later

The installer auto-detects and removes the previous version, but it also
**re-installs its own bundled TensorFlow**. After every PixInsight upgrade,
remove it again:

```bash
sudo rm /opt/PixInsight/bin/lib/libtensorflow*
```

If you accidentally launched PixInsight before removing them, close it, remove
the libraries, and reboot:

```bash
sudo rm /opt/PixInsight/bin/lib/libtensorflow*
sudo reboot
```

Re-running `./setup-cuda-pixinsight.sh` after dropping a newer PixInsight
tarball into `~/Downloads` also handles this — use `--reset` first if you want
it to redo the PixInsight steps.

---

## Troubleshooting

### `nvidia-smi` no longer sees your driver

Sometimes a bad update breaks the driver. Purge and reinstall it:

```bash
./setup-cuda-pixinsight.sh --repair-driver
```

Manual equivalent:

```bash
sudo apt-get purge -y 'nvidia*'
sudo apt autoremove -y
sudo apt autoclean
sudo apt update
sudo ubuntu-drivers install
sudo reboot
nvidia-smi
```

### Check the whole stack

```bash
./setup-cuda-pixinsight.sh --verify
```

This confirms the driver, `nvcc`, cuDNN, TensorFlow, and that PixInsight is set
to use the system TensorFlow.

---

## Optional tweaks

### Install the KDE Plasma desktop on top of plain Ubuntu

If you installed Ubuntu (GNOME) and want the Kubuntu experience:

```bash
sudo apt install kde-standard
```

During install you'll be asked to pick `gdm3` or `sddm` — choose **sddm**. If an
on-screen keyboard appears at boot, disable it:

```bash
sudo nano /etc/sddm.conf
# add:
InputMethod=
```

### Faster NTFS driver for a shared Windows data drive (`ntfs3`)

If your imaging data lives on an NTFS drive shared with Windows, Kubuntu may
mount it with the slow `ntfs-3g` (FUSE) driver. Switching to the in-kernel
`ntfs3` driver roughly **halved** WBPP processing time on an NTFS drive in
testing.

```bash
# Are you on the slow driver? "fuseblk" = ntfs-3g (slow), "ntfs3" = fast
mount | grep ntfs

# Find the drive's UUID and mount point
sudo lsblk -f
```

Edit `/etc/fstab` and change the NTFS partition's line from `ntfs-3g` to
`ntfs3`, e.g.:

```text
UUID=YOUR-UUID-HERE  /mnt/yourmount  ntfs3  defaults,noatime,uid=1000,gid=1000  0 0
```

Then remount and verify:

```bash
sudo umount /mnt/yourmount
sudo mount -a
mount | grep ntfs   # should now show "type ntfs3"
```

---

## Notes & disclaimer

- Versions here are pinned because they're known to work **together**. If you
  bump one (e.g. a newer CUDA), check the
  [TensorFlow build matrix](https://www.tensorflow.org/install/source#gpu) for a
  compatible TensorFlow version.
- Editing `/etc/fstab` incorrectly can prevent your system from booting — double
  check the UUID and mount point before rebooting.
- This is a community guide, not affiliated with PixInsight, RC Astro, or NVIDIA.

## License

Released under the [MIT License](./LICENSE). PixInsight, cuDNN, and the NVIDIA
drivers/toolkit have their own licenses — this repo only automates their
installation and redistributes none of them.

## Contributing

`main` is protected: changes land via pull request and must pass CI
(shellcheck + markdownlint) before merge.
