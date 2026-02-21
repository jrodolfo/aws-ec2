# .bashrc

# Enable git branch in prompt
if [ -f /usr/share/git-core/contrib/completion/git-prompt.sh ]; then
    source /usr/share/git-core/contrib/completion/git-prompt.sh
fi

get_aws_profile() {
    if [ -n "$AWS_PROFILE" ]; then
        echo "($AWS_PROFILE)"
    fi
}

get_git_branch_prompt() {
    if declare -F __git_ps1 >/dev/null 2>&1; then
        __git_ps1 '(%s)'
    fi
}

# Source global definitions
if [ -f /etc/bashrc ]; then
	. /etc/bashrc
fi

# User specific environment
if ! [[ "$PATH" =~ "$HOME/.local/bin:$HOME/bin:" ]]
then
    PATH="$HOME/.local/bin:$HOME/bin:$PATH"
fi
export PATH

# Uncomment the following line if you don't like systemctl's auto-paging feature:
# export SYSTEMD_PAGER=

# User specific aliases and functions
if [ -d ~/.bashrc.d ]; then
	for rc in ~/.bashrc.d/*; do
		if [ -f "$rc" ]; then
			. "$rc"
		fi
	done
fi

unset rc

# Alias
alias ll='ls -lh'
alias la='ls -lha'
alias cls='clear'
alias l.='ls -dl .*'

export PATH="$HOME/bin:$PATH"
export PATH="$HOME/.cargo/bin:$PATH"

# scripts from the tools folder
export PATH="$HOME/.local/bin:$PATH"

# fzf shell integration (Linux paths)
if [ -f /usr/share/fzf/shell/completion.bash ]; then
    . /usr/share/fzf/shell/completion.bash
fi
if [ -f /usr/share/fzf/shell/key-bindings.bash ]; then
    . /usr/share/fzf/shell/key-bindings.bash
fi
if [ -f /usr/share/fzf/completion.bash ]; then
    . /usr/share/fzf/completion.bash
fi
if [ -f /usr/share/fzf/key-bindings.bash ]; then
    . /usr/share/fzf/key-bindings.bash
fi

HISTSIZE=10000
HISTFILESIZE=10000
HISTCONTROL=ignoredups:erasedups
shopt -s histappend
PROMPT_COMMAND="history -a; history -c; history -r; $PROMPT_COMMAND"

# Colors
GREEN="\[\e[32m\]"
RED="\[\e[31m\]"
YELLOW="\[\e[33m\]"
CYAN="\[\e[36m\]"
BLUE="\[\e[34m\]"
RESET="\[\e[0m\]"

# Date function
now() {
    date "+%Y-%m-%d %H:%M:%S"
}

# Prompt
# export PS1="${GREEN}\u@\h${RESET} ${RED}\W${RESET} ${YELLOW}\$(__git_ps1 '(%s)')${RESET} ${CYAN}\$(get_aws_profile)${RESET} ${BLUE}[\$(now)]${RESET} \$ "
# Color prompt: RED for root, several colours for normal user
if [ "$EUID" -eq 0 ]; then
    # ROOT USER - red
    export PS1='\[\e[1;31m\]\u@\h:\w# \[\e[0m\]'
else
    # NORMAL USER - green
    export PS1="${GREEN}\u@\h${RESET} ${RED}\W${RESET} ${YELLOW}\$(get_git_branch_prompt)${RESET} ${CYAN}\$(get_aws_profile)${RESET} ${BLUE}[\$(now)]${RESET} \$ "
fi
