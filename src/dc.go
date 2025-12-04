package main

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
)

// execDockerComposeCommand executes docker-compose commands
func execDockerComposeCommand(args ...string) string {
	cmd := exec.Command("docker-compose", args...)
	output, err := cmd.Output()
	if err != nil {
		return err.Error()
	}
	return string(output)
}

// execDockerComposeCommandWithError executes docker-compose commands with proper I/O
func execDockerComposeCommandWithError(args ...string) error {
	cmd := exec.Command("docker-compose", args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Stdin = os.Stdin
	return cmd.Run()
}

// Docker Compose Operations
func composeUp() string {
	return execDockerComposeCommand("up")
}

func composeUpDetached() string {
	return execDockerComposeCommand("up", "-d")
}

func composeDown() string {
	return execDockerComposeCommand("down")
}

func composePs() string {
	return execDockerComposeCommand("ps")
}

func composeLogs(service string) string {
	if service != "" {
		return execDockerComposeCommand("logs", service)
	}
	return execDockerComposeCommand("logs")
}

func composeExec(service string, command string) string {
	return execDockerComposeCommand("exec", service, "sh", "-c", command)
}

func composeRestart(service string) string {
	if service != "" {
		return execDockerComposeCommand("restart", service)
	}
	return execDockerComposeCommand("restart")
}

func composeStop(service string) string {
	if service != "" {
		return execDockerComposeCommand("stop", service)
	}
	return execDockerComposeCommand("stop")
}

func composeStart(service string) string {
	if service != "" {
		return execDockerComposeCommand("start", service)
	}
	return execDockerComposeCommand("start")
}

func composeBuild() string {
	return execDockerComposeCommand("build")
}

func composePull() string {
	return execDockerComposeCommand("pull")
}

func composeConfig() string {
	return execDockerComposeCommand("config")
}

func composeRun(service string) string {
	return execDockerComposeCommand("run", service)
}

func main() {
	args := os.Args[1:]

	if len(args) == 0 {
		fmt.Println("Docker Compose utility - Shortcuts for common docker-compose commands")
		fmt.Println()
		fmt.Println("Usage: dc [command]")
		fmt.Println()
		fmt.Println("Commands:")
		fmt.Println("  up                    - Start services")
		fmt.Println("  up -d                 - Start services in background")
		fmt.Println("  down                  - Stop and remove services")
		fmt.Println("  ps                    - List services")
		fmt.Println("  logs [service]        - View logs for service")
		fmt.Println("  exec [service] [cmd]  - Execute command in service")
		fmt.Println("  restart [service]     - Restart specific service")
		fmt.Println("  stop [service]        - Stop specific service")
		fmt.Println("  start [service]       - Start specific service")
		fmt.Println("  build                 - Build services")
		fmt.Println("  pull                  - Pull service images")
		fmt.Println("  config                - Validate and view config")
		fmt.Println("  run [service]         - Run one-time command for service")
		fmt.Println()
		return
	}

	switch args[0] {
	case "up":
		if len(args) > 1 && args[1] == "-d" {
			if err := execDockerComposeCommandWithError("up", "-d"); err != nil {
				fmt.Printf("Error: %v\n", err)
			}
		} else {
			// For up command, we need to handle interactive mode properly
			if err := execDockerComposeCommandWithError("up"); err != nil {
				fmt.Printf("Error: %v\n", err)
			}
		}
	case "down":
		fmt.Print(composeDown())
	case "ps":
		fmt.Print(composePs())
	case "logs":
		service := ""
		if len(args) > 1 {
			service = args[1]
		}
		if service != "" {
			if err := execDockerComposeCommandWithError("logs", service); err != nil {
				fmt.Printf("Error: %v\n", err)
			}
		} else {
			if err := execDockerComposeCommandWithError("logs"); err != nil {
				fmt.Printf("Error: %v\n", err)
			}
		}
	case "exec":
		if len(args) < 3 {
			fmt.Println("Usage: dc exec [service] [command]")
			return
		}
		service := args[1]
		command := strings.Join(args[2:], " ")
		if err := execDockerComposeCommandWithError("exec", "-it", service, "sh", "-c", command); err != nil {
			fmt.Printf("Error: %v\n", err)
		}
	case "restart":
		service := ""
		if len(args) > 1 {
			service = args[1]
		}
		fmt.Print(composeRestart(service))
	case "stop":
		service := ""
		if len(args) > 1 {
			service = args[1]
		}
		fmt.Print(composeStop(service))
	case "start":
		service := ""
		if len(args) > 1 {
			service = args[1]
		}
		fmt.Print(composeStart(service))
	case "build":
		fmt.Print(composeBuild())
	case "pull":
		fmt.Print(composePull())
	case "config":
		fmt.Print(composeConfig())
	case "run":
		if len(args) < 2 {
			fmt.Println("Usage: dc run [service]")
			return
		}
		service := args[1]
		if err := execDockerComposeCommandWithError("run", "-it", service); err != nil {
			fmt.Printf("Error: %v\n", err)
		}
	default:
		// Execute the command directly if not a shortcut
		fmt.Print(execDockerComposeCommand(args...))
	}
}