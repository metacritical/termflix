tmux_status_left()
{

		if [ $(battery | grep -P '([0-9].+)') -lt '20' ]; then
				stat_color=196;
		else
				stat_color=46;
		fi
		
		$(tmux set-option -g status-left "#[bg=colour234]#[fg=colour$stat_color,bold]#(battery)")
}

tmux_status_left
