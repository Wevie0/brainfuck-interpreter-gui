# brainfuck-interpreter-gui

## A Brainfuck Text Editor, Interpreter, and Turing Machine Simulator

An integrated development environment for the esolang Brainfuck. It includes a text editor with syntax highlighting, an interpreter, debugging with stepping, and Turing Machine simulator.

## Demo
![image](https://github.com/user-attachments/assets/ee1274e0-6152-4027-8627-01b7fa57de31)

## How to test and run the interpreter

**Ensure you have the [nix package manager](https://nixos.org/download/) installed or the code will not compile!**

To test the interpreter functionality, simply run `make` from the root directory or `make test`.

To use the interpreter, simply run the command `stack exec brainfuck-interpreter-gui-exe -- -f "PATH TO FILE"` (without the `""`) to open a `.bf` file or `stack exec brainfuck-interpreter-gui-exe -- -s STRING` to directly interpret a brainfuck string. (Technically you could run this through ghci, but it returns a `tape`, which is an infinite piece of data so you probably don't want to `show` that.)

To run the GUI, run the command `stack exec brainfuck-interpreter-gui-exe -- -g` or run the command `make gui`. You can also run `stack ghci`/`make ghci`, then run `:l GUITest` followed by `run`.

### Dependencies

|Haskell Libraries|Packages (via Nix)|
|-|-|
|base|glib|
|binary|gobject-introspection|
|containers|pcre2|
|silently|freetype|
|gi-gtk|cairo|
|freetype2|expat|
|cairo|fontconfig|
|haskell-gi-base|util-linux|
|text|harfbuzz|
|mtl|libselinux|
|gi-glib|libsepol|
|gi-gdk|pkg-config|
|gi-gobject|xorg.libXdmcp|
||gtk3|
||lerc|
||libthai|
||libdatrie|
||libxkbcommon|
||libepoxy|
||xorg.libXtst|
||libsysprof-capture|

## License

This project is licensed under the [GNU General Public License v3.0](./LICENSE).
