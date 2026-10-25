# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH

# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"
export PATH="$PATH:$HOME/go/bin"

export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
export PATH="$JAVA_HOME/bin:$PATH"
export PATH="$HOME/.npm-global/bin:$PATH"
[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"

export ANDROID_HOME="$HOME/Android/Sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export ANDROID_NDK_HOME="$ANDROID_HOME/ndk/29.0.14206865"

export PATH="/opt/android-sdk/cmdline-tools/latest/bin:$PATH"
export PATH="$ANDROID_HOME/platform-tools:$PATH"

export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time Oh My Zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="robbyrussell"

# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in $ZSH/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment one of the following lines to change the auto-update behavior
# zstyle ':omz:update' mode disabled  # disable automatic updates
# zstyle ':omz:update' mode auto      # update automatically without asking
# zstyle ':omz:update' mode reminder  # just remind me to update when it's time

# Uncomment the following line to change how often to auto-update (in days).
# zstyle ':omz:update' frequency 13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# You can also set it to another string to have that shown instead of the default red dots.
# e.g. COMPLETION_WAITING_DOTS="%F{yellow}waiting...%f"
# Caution: this setting can cause issues with multiline prompts in zsh < 5.7.1 (see #5765)
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(
    git
    zsh-syntax-highlighting
    zsh-autosuggestions
)

source $ZSH/oh-my-zsh.sh

# User configuration

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='nvim'
# fi

# Compilation flags
# export ARCHFLAGS="-arch $(uname -m)"

# Set personal aliases, overriding those provided by Oh My Zsh libs,
# plugins, and themes. Aliases can be placed here, though Oh My Zsh
# users are encouraged to define aliases within a top-level file in
# the $ZSH_CUSTOM folder, with .zsh extension. Examples:
# - $ZSH_CUSTOM/aliases.zsh
# - $ZSH_CUSTOM/macos.zsh
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"

alias start_mongo="mongod --dbpath /var/lib/mongodb"
alias start_arango="arangod --configuration none --server.endpoint tcp://127.0.0.1:8529 --database.directory /var/lib/arangodb3 --javascript.startup-directory /usr/share/arangodb3/js --javascript.app-path /var/lib/arangodb3-apps"
alias start_arangosh="docker exec -t arangodb arangosh --server.password=password"
start_sql_server() {
    docker run -e "ACCEPT_EULA=Y" \
        -e "MSSQL_SA_PASSWORD=${MSSQL_SA_PASSWORD:?set it in ~/.zshrc.local}" \
        -p 1433:1433 \
        --name sqlserver \
        -v mssql_data:/var/opt/mssql \
        -d mcr.microsoft.com/mssql/server:2022-latest
}
alias tgauth="yaauth telegram --config ~/develop/telegram.config.example.json"
alias antigravity="~/.local/bin/agy"
alias brave-browser="brave-flatpak"

# pnpm
export PNPM_HOME="/home/oleksandr/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end


export HISTFILE=~/.zsh_history
export SAVEHIST=10000
export HISTSIZE=10000
setopt HIST_IGNORE_DUPS
setopt SHARE_HISTORY

autoload -U colors && colors

center_text() {
    local text="$1"
    local columns=$(tput cols)
    local text_length=${#text}
    local padding=$(( (columns - text_length) / 2))

    if [ "$padding" -gt 0 ]; then
        printf "%*s%s\n" "$padding" "" "$text"
    else
        echo "$text"
    fi
}

ascii_banner() {
echo -e "\e[32m"
center_text "@@(@@%@@@@@@@@%@@@ @/@@@@/,&(@.%@@@@(@@@@@@@@%(@&.@@&*@@@@@@@@(@,%@@@@@#@@@.@#(@@*@@@@@@@@#*@#@@@*(&@@@&& @@@@@@@#@@@@@&"
center_text "@@(@@%@@@@@@@@%@@@.,@@@@@ &&&@(&(@@@@*@@@@@@@@&@@*,@@ %@@@@@@@@/@.@@@@@%@@@.&%%@@*@@@@@@@@#/@&@@@.@.@%@@%*/@@@@@@&@@@@@@"
center_text "&@#@@@@@@@@@@@%@@@ %@@@@*(&&@*@#&/@#%(%#####%@#%@*@#@&,@@@@@@@@@#@/@@@@@@@@,@&#&&*#%##%&@@((&@/@@%@&.@%@@# @@@@@@@%@@@@@"
center_text "@&&@@@@@@@@@@@&@@@ @@&@@ @@@@@@*@@(@@@,@@@@@@@(#@(&%&@./@@@@@@@@@&@/@@@@&@@#@@(&@#*@@@@@@@##@@&@@@#&@*@%@@((@@@@@@(@@@@@"
center_text "@@@&@@&@@@@@@@@@@@.@@/@*&&&@@@(@#&@(@@@,@@@@@@%@@&&@(@%&/@@@@@#@@@(&#@@@%@&@@@&#@%&@@@&%#&/(%@@%@@#&&&#&&@@,@@@@@@&@@@@@"
center_text "@@@#@@@@@@@@@@@%@@*@%&@.@@@@@@@%#@&&/@%#%#((((@%#@%@@/@/@(@@@@%@@@%%(&@@#@/@@@&/@@@#*.  .#,,/#@#@@%@&&%&#%@@(@@@@@@%@@@@"
center_text "@%@(@@@&@@@@@@@#@@##.@&%@@@@@@@%( ,** #. .  ,@@(*%%@@@(&@&(@@@@,@@@%@(@%%@,@@@%(,    ,,. ...     @/%@@&(@/&@#@@@@@@(@@@@"
center_text ",.&&@@@@@@@@@@@&@@@*%@*@@#@(.   *((((///,*/. (   /@@@@@#/@@/@@@%/@@#&@&@(&%@@(*(@ #,(#%(#%/,/.%@@@* *,@#,@(%@#@@@@@&@@@@"
center_text "@@& %@@@@@@@@@@@&@@,@@*& */@@/ %#%/%%%%((/(% %@@@@#%@@@@@#@@*@@@.%@&@@@#&*@&@@@@@@@&*&#%(.&%&*/@@@@@@&,*%*@%##@@@@@@%@@@"
center_text ".@@@(@@@@@@@@@@@#@@(@##&@@@@@@@@@&/&#((#*&@@,(@@@@@@@@@@@@&@@&%@#@%@@@@%@*%@@@@@&.@@%@//*#%@@.&@@@@@&%%%%@*@@(&@@@@@/@@@"
center_text "@#* #@@@@@@@@@@@&@@@#.&&&@@@@@*.@@@%@((/@&@@ @@@@@@@@@@@@@@@@@@@@%@%@@@@&@@&@@@@@.@@@@@@@@@@./@@@@&&%&@@@@&*@@/@@@@@&@@&"
center_text "@@&@@(@@@@@@@@@@@%@@/ &%&%%@@@@@ @@@@@@@@@%,,&@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&*&%/ .,,. *%%&@@@@@@@@ %@.@@@@@@#@&"
center_text ".,@%@ @@@@@@@@@@@#@@# @@@@@@&&&./%@@#@@@@&@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&/. ((@@@@@(@@"
center_text "@%@#@(/@@@@@@@@@@@&@@.@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@%@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@,..*(@@@@@&@@"
center_text "@#@@@@*@@@@@@@@@@@#@@*%@@@@@@@@@@@@&@&&@@@@@@@@@@@@@@@@@@&&@@@@@@@#@@@@@@@&@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@% .&&@&@@@@@#@"
echo -e "\e[0m"
}

#ascii_banner


export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# bun completions
[ -s "/home/oleksandr/.bun/_bun" ] && source "/home/oleksandr/.bun/_bun"

export BROWSER=brave-flatpak
alias opentabletdriver="/usr/lib/opentabletdriver/OpenTabletDriver.UX.Gtk"
export PATH="$PATH:/opt/mssql-tools18/bin"
export PATH="$PATH:$HOME/.dotnet/tools"


# Added by Antigravity CLI installer
export PATH="/home/oleksandr/.local/bin:$PATH"

# zoxide: learns every directory you cd into (z / zi to jump, yazi's Z lists them); keep at the end of .zshrc
if command -v zoxide >/dev/null; then
    eval "$(zoxide init zsh)"
fi
