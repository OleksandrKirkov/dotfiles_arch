# dotfiles

## Installation

```sh
git clone https://github.com/OleksandrKirkov/dotfiles.git
cd ~/dotfiles
```

```sh
chmod +x install.sh
./install.sh 
```

```sh
cp ~/dotfiles-arch/.zshrc ~/.zshrc
```

```sh
cp -r ~/dotfiles-arch/.config/* ~/config 

cp ~/dotfiles-arch/.gitconfig ~/.gitconfig
cp ~/dotfiles-arch/.git-credentials ~/.git-credentials

git config --global credential.helper store
```
