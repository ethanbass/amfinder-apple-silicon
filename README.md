# Automatic Mycorrhiza Finder (AMFinder)

The Automatic Mycorrhiza Finder (AMFinder) consists of the `amf` Python script
for automatic annotation of AM fungal colonization and fungal structures in
root images, and the standalone interface `amfbrowser` for inspection,
amendment and validation of computer predictions.


## Summary

1. [Command-line script (`amf`)](#amf)
2. [Standalone interface (`amfbrowser`)](#amfbrowser)

## Command-line script (`amf`)<a name="amf"></a>

The command-line script `amf` uses convolutional neural networks (ConvNets)
to predict **fungal root colonisation** (prediction stage 1) and **intraradical
hyphal structures** (prediction stage 2). The program uses pre-trained ConvNets
adapted to ink-stained root pictures. It can also train ConvNets on
**custom datasets** to enable analysis of differently stained
or labelled root images.

### Installation instructions

The command-line program `amf` requires [Python](https://www.python.org/)
**version 3.6** or above.
It is recommended to create a virtual environment to install the packages
listed in the dependency file `requirements.txt`. Below is an example of a
typical installation, followed by a test prediction.

```bash
$ python3.7 -m venv amfenv
$ source amfenv/bin/activate
(amfenv) $ python -m pip install -r requirements.txt
(amfenv) $ ./amf predict test/*jpg
(amfenv) $ deactivate
```

### Prediction mode

This is the mode to use when predicting structures on root images.

```bash
$ amf predict [-t tile_edge] [-net model] [IMAGE [IMAGE] ...]
```

### Training mode

Users may want to train `amf` on a specific set of images. This is especially
useful when analysing root images obtained with different **staining methods**
(such as trypan blue or chlorazol black) or that rely on **fluorescence**
(such as AlexaFluor-conjugated Wheat Germ Agglutinin).

```bash
$ amf train [IMAGE [IMAGE] ...]
```

Command-line options are as follows:

|Short|Long|Description|Default|
|-|-|-|-|
|`-h`|`--help`|Display this help.|
|`-t`|`--tile_size`| Tile size, in pixels.|126|
|`-b`|`batch_size`|Training batch size.|32|
|`-k`|`--keep_background`|Do not skip any background tile.|False|
|`-a`|`--data_augmentation`|Activate data augmentation.|False|
|`-s`|`--summary`|Save CNN architecture and graph.|False|
|`-o`|`--outdir`|Folder where to save trained model and CNN architecture.|cwd|
|`-e`|`--epochs`|Number of training cycles.|100|
|`-p`|`--patience`|Number of epochs to wait before early stopping.|12|
|`-lr`|`--learning_rate`|Learning rate used by the Adam optimiser.|0.001|
|`-vf`|`--validation_fraction`|Fraction of tiles used as validation set.|15%|
|`-1`|`--CNN1`|Train for root colonisation.|True|
|`-2`|`--CNN2`|Train for intraradical hyphal structures.|False|
|`-net`|`--network`|Name of the pre-trained network.|None|

For large datasets, running the script on a high-performance computing (HPC)
equipment is recommended. An example using [Slurm](https://slurm.schedmd.com/)
workload manager is provided below.

```bash
#! /bin/bash
#SBATCH -e train.err
#SBATCH -o train.out
#SBATCH --mem=100G
#SBATCH -n 48

source /home/user/amfenv/bin/activate
./amf train dataset/*jpg
deactivate
```


## Standalone interface (`amfbrowser`)<a name="amfbrowser"></a>

The standalone interface `amfbrowser` allows to browse, amend and validate
`amf` predictions. Installation instructions are detailed below for the main
platforms.

![](doc/amfbrowser.png)

### Installation instructions<a name="amfbrowseronlinux"></a>

#### Linux

1. Download and install the OCaml package manager
[OPAM](https://opam.ocaml.org/doc/Install.html).

2. Using [`opam switch`](https://opam.ocaml.org/doc/Usage.html#opam-switch),
install **OCaml 4.08.0** (older versions won't work).

3. Install `amfbrowser` dependencies:
```bash
$ opam install dune odoc lablgtk cairo2 cairo2-gtk magic-mime camlzip
```
You may be required to install development packages, including
`libgtk2.0-dev` and `libgtksourceview2.0-dev`.

4. Retrieve `amfbrowser` sources and build:
```
$ git clone git@github.com:SchornacklabSLCU/amfinder.git
$ cd amfinder/amfbrowser
$ ./build.sh
```

5. The binary `amfbrowser.exe` is ready to use (see [next section](#amfbrowserhelp)).



#### MacOS

#### Windows 10

`amfbrowser` can be installed and run on Windows 10 after activation of the
Windows Subsystem for Linux (WSL). WSL runs a a GNU/Linux environment directly
on Windows, unmodified. **Admin rights are required to activate WSL**.

1. Activate the [Windows Subsystem for Linux
(WSL)](https://docs.microsoft.com/en-us/windows/wsl/install-win10). Then, go to
Windows App store and install a Linux distribution
(recommended distributions are [Ubuntu](https://ubuntu.com/) and
[Debian](https://www.debian.org/index.html), but many others should work too).

2. Install an OCaml build system based on the `brew` package manager:
```bash
$ sudo apt update
$ sudo apt upgrade
$ sudo apt autoclean
$ sudo apt install curl build-essential git
$ sh -c "$(curl -fsSL https://raw.githubusercontent.com/Linuxbrew/install/master/install.sh)"
$ test -d ~/.linuxbrew && eval $(~/.linuxbrew/bin/brew shellenv)
$ test -d /home/linuxbrew/.linuxbrew && eval $(/home/linuxbrew/.linuxbrew/bin/brew shellenv)
$ test -r ~/.bash_profile && echo "eval \$($(brew --prefix)/bin/brew shellenv)" >> ~/.bash_profile
$ echo "eval \$($(brew --prefix)/bin/brew shellenv)" >> ~/.profile
$ brew install gpatch opam gtk+ cairo
```

3. Follow the [Linux installation instructions](#amfbrowseronlinux). Please note
that sandboxing does not work on Windows. OPAM should be initialized using
`opam init --disable-sandboxing`.

4. Install a X server (for instance, [Xming](https://sourceforge.net/projects/xming/),
then configure bash to tell GUIs to use the local X server. For instance, use
`echo "export DISPLAY=localhost:0.0" >> ~/.bashrc`. Detailed instructions are
available on the internet.
