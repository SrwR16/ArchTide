# Fish completions for flow-cli

function __flow_needs_command
    set -l tokens (commandline -opc)
    if test (count $tokens) -eq 1
        return 0
    end
    return 1
end

function __flow_using_command
    set -l cmd $argv[1]
    set -l tokens (commandline -opc)
    if test (count $tokens) -ge 2
        and test "$tokens[2]" = "$cmd"
        return 0
    end
    return 1
end

# Disable file completions
complete -c flow -f

# Main commands
complete -c flow -n '__flow_needs_command' -a 'run' -d 'Start the Flow Shell'
complete -c flow -n '__flow_needs_command' -a 'reload' -d 'Reload the currently running shell'
complete -c flow -n '__flow_needs_command' -a 'debug' -d 'Run the shell in debug mode'
complete -c flow -n '__flow_needs_command' -a 'exit' -d 'Stop the Flow Shell'
complete -c flow -n '__flow_needs_command' -a 'logs' -d 'Show Quickshell logs'
complete -c flow -n '__flow_needs_command' -a 'spotlight' -d 'Toggle the Spotlight search panel'
complete -c flow -n '__flow_needs_command' -a 'dashboard' -d 'Toggle the Dashboard'
complete -c flow -n '__flow_needs_command' -a 'settings' -d 'Open the Flow Settings panel'
complete -c flow -n '__flow_needs_command' -a 'launcher' -d 'Toggle the App Launcher'
complete -c flow -n '__flow_needs_command' -a 'notifications' -d 'Toggle the Notification Center'
complete -c flow -n '__flow_needs_command' -a 'quicksettings' -d 'Toggle the Quick Settings'
complete -c flow -n '__flow_needs_command' -a 'systemmonitor' -d 'Toggle the System Monitor'
complete -c flow -n '__flow_needs_command' -a 'overview' -d 'Toggle the Overview panel'
complete -c flow -n '__flow_needs_command' -a 'session' -d 'Toggle the Session menu'
complete -c flow -n '__flow_needs_command' -a 'region' -d 'Region tools'
complete -c flow -n '__flow_needs_command' -a 'reboot' -d 'Reboot the system'
complete -c flow -n '__flow_needs_command' -a 'lock' -d 'Lock the screen using Flow Shell'
complete -c flow -n '__flow_needs_command' -a 'poweroff' -d 'Shut down the system'
complete -c flow -n '__flow_needs_command' -a 'status' -d 'Show current shell status'
complete -c flow -n '__flow_needs_command' -a 'config' -d 'Manage configuration'
complete -c flow -n '__flow_needs_command' -a 'doctor' -d 'Check system health'
complete -c flow -n '__flow_needs_command' -a 'update' -d 'Check and install updates'
complete -c flow -n '__flow_needs_command' -a 'install' -d 'Install Flow Shell'
complete -c flow -n '__flow_needs_command' -a 'wallpaper' -d 'Manage wallpaper'
complete -c flow -n '__flow_needs_command' -a 'theme' -d 'Manage dark/light mode'
complete -c flow -n '__flow_needs_command' -a 'colorscheme' -d 'Regenerate the colorscheme'
complete -c flow -n '__flow_needs_command' -a 'version' -d 'Show version'
complete -c flow -n '__flow_needs_command' -a 'help' -d 'Show help'

# Subcommands
complete -c flow -n '__flow_using_command install' -a 'deps' -d 'Install shell dependencies only'
complete -c flow -n '__flow_using_command update' -a 'shell cli stable canary'
complete -c flow -n '__flow_using_command wallpaper' -a 'cycle'
complete -c flow -n '__flow_using_command theme' -a 'dark light toggle'
complete -c flow -n '__flow_using_command spotlight' -a 'files apps commands clipboard emoji'
complete -c flow -n '__flow_using_command region' -a 'screenshot search ocr record record-audio'
complete -c flow -n '__flow_using_command config' -a 'edit'
