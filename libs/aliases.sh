#Alias List by permissions
alias _='sudo'
# alias l='ls -CF --color=auto'
alias ls='ls --color=auto'
alias la='ls -A --color=auto'
#alias lsv='ls -v --color=auto'
#alias lsd='ls -l --color=auto'
#alias ll='ls -alF --color=auto'
# alias db:c='rake db:create'
# alias db:m='rake db:migrate'
# alias db:d='rake db:drop'
# alias db:s='rake db:seed'
alias db:sup='rake db:setup'
alias db:red='rake db:migrate:redo'
alias rmrf='rm -rf'
alias ccat='e2ansi-cat'
alias rs='rails server'
alias rc='rails c'
alias ss='script/server'
alias sc='script/console'
alias emacs="emacs -nw"
alias tmux="TERM=screen-256color-bce tmux"
alias sbts='a=$(pwd);cd $a'
#alias rm='rm -i'
alias :q='exit 0'
alias :Q='exit 0'
alias jira_pass='cat ~/Documents/creds.txt | xclip -i -selection clipboard'
#alias speedtest='wget --output-document=/dev/null http://speedtest.wdc01.softlayer.com/downloads/test500.zip'
#alias speedtest='speedtest-cli'
alias rgrep='grep --color=auto -r -n2 '
alias ~='cd ~'
alias ..="cd ../../"
alias ...="cd ../../../"
alias ....="cd ../../../../"

# alias cljs="clj -Sdeps '{:deps {org.clojure/clojurescript {:mvn/version \"1.9.946\"}}}' -J--add-modules -Jjava.xml.bind -m cljs.repl.node"
alias cljs="clj -m cljs.repl.node"
alias cljrebl='clj -J-Dclojure.server.repl="{:port 3742 :accept clojure.core.server/repl}" -A:rebl'
alias cljsrebl="clj  -J--add-modules -Jjava.xml.bind -Sdeps '{:deps {github-mfikes/cljs-main-rebel-readline {:git/url \"https://gist.github.com/mfikes/9f13a8e3766d51dcacd352ad9e7b3d1f\" :sha \"27b82ef4b86a70afdc1a2eea3f53ed1562575519\"}}}' -i @setup.clj -m cljs.main"
alias serve="ruby -run -ehttpd $ARGV[0] -p8000"
alias less="less --RAW-CONTROL-CHARS"
alias fig="rlwrap lein figwheel"
alias csi="rlwrap csi"
alias pg-start="launchctl load ~/Library/LaunchAgents/homebrew.mxcl.postgresql.plist"
alias pg-stop="launchctl unload ~/Library/LaunchAgents/homebrew.mxcl.postgresql.plist"
alias pflx="src;peerflix '$(pbpaste)' -v"
alias stream="torrent"
alias st="torrent"
alias cljclr="mono $CLOJURE_LOAD_PATH/Clojure.Main.exe"
alias cljcomp="mono $CLOJURE_LOAD_PATH/Clojure.Compile.exe"
alias icloudrive="cd ~/Library/Mobile\ Documents/com~apple~CloudDocs"
alias screen_record="osascript -e 'tell application \"QuickTime Player\" to activate' -e 'tell application \"QuickTime Player\" to start (new screen recording)'"

src () {
    echo -e "\033[48;5;1mReloading...\033[0m\n"
    source ~/.bash_profile
    if [ $? -eq 0 ];then
       clear
    fi
}

unblock(){
    lsof -ti :$1 | kill -s SIGKILL $1 TERM
}

timeloop () {
    while true; do
        timeout -s SIGTSTP -k 62m 60m $@;
    done;
}
