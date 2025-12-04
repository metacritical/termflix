package main

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
)

// execDockerCommand executes docker commands
func execDockerCommand(args ...string) string {
	cmd := exec.Command("docker", args...)
	output, err := cmd.Output()
	if err != nil {
		return err.Error()
	}
	return string(output)
}

// execDockerComposeCommand executes docker-compose commands
func execDockerComposeCommand(args ...string) string {
	cmd := exec.Command("docker-compose", args...)
	output, err := cmd.Output()
	if err != nil {
		return err.Error()
	}
	return string(output)
}

// execDockerCommandWithError executes docker commands and handles errors appropriately
func execDockerCommandWithError(args ...string) error {
	cmd := exec.Command("docker", args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Stdin = os.Stdin
	return cmd.Run()
}

// execDockerComposeCommandWithError executes docker-compose commands with proper I/O
func execDockerComposeCommandWithError(args ...string) error {
	cmd := exec.Command("docker-compose", args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Stdin = os.Stdin
	return cmd.Run()
}

// Docker Container Operations
func listRunningContainers() string {
	return execDockerCommand("ps", "--format", "table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}")
}

func listAllContainers() string {
	return execDockerCommand("ps", "-a", "--format", "table {{.ID}}\t{{.Names}}\t{{.Status}}")
}

func listImages() string {
	return execDockerCommand("images", "--format", "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}")
}

func listVolumes() string {
	return execDockerCommand("volume", "ls", "--format", "table {{.Driver}}\t{{.Name}}")
}

func listNetworks() string {
	return execDockerCommand("network", "ls", "--format", "table {{.ID}}\t{{.Name}}\t{{.Driver}}\t{{.Scope}}")
}

func systemDf() string {
	return execDockerCommand("system", "df")
}

func systemPrune() string {
	return execDockerCommand("system", "prune", "-f")
}

func dockerInfo() string {
	return execDockerCommand("info")
}

func dockerVersion() string {
	return execDockerCommand("--version")
}

func dockerStats() string {
	return execDockerCommand("stats", "--no-stream")
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

func composeBuild() string {
	return execDockerComposeCommand("build")
}

func composeConfig() string {
	return execDockerComposeCommand("config")
}

func main() {
	args := os.Args[1:]

	if len(args) == 0 {
		fmt.Println("Docker utility - Shortcuts for common Docker commands")
		fmt.Println()
		fmt.Println("Usage: dd [command]")
		fmt.Println()
		fmt.Println("Docker commands:")
		fmt.Println("  ps                    - List running containers")
		fmt.Println("  ls | containers       - List all containers")
		fmt.Println("  img | images          - List images")
		fmt.Println("  vol | volumes         - List volumes")
		fmt.Println("  net | networks        - List networks")
		fmt.Println("  df                    - Show disk usage")
		fmt.Println("  prune                 - Remove unused data")
		fmt.Println("  info                  - Show system info")
		fmt.Println("  version               - Show version")
		fmt.Println("  stats                 - Show resource usage")
		fmt.Println()
		fmt.Println("Container operations:")
		fmt.Println("  start [container]     - Start container")
		fmt.Println("  stop [container]      - Stop container")
		fmt.Println("  restart [container]   - Restart container")
		fmt.Println("  rm [container]        - Remove container")
		fmt.Println("  logs [container]      - View container logs")
		fmt.Println("  exec [container] [cmd] - Execute command in container")
		fmt.Println("  run [image] [args]    - Run container")
		fmt.Println()
		return
	}

	// Handle regular Docker commands
	switch args[0] {
	case "ps":
		fmt.Print(listRunningContainers())
	case "ls", "containers":
		fmt.Print(listAllContainers())
	case "img", "images":
		fmt.Print(listImages())
	case "vol", "volumes":
		fmt.Print(listVolumes())
	case "net", "networks":
		fmt.Print(listNetworks())
	case "df":
		fmt.Print(systemDf())
	case "prune":
		fmt.Print(systemPrune())
	case "info":
		fmt.Print(dockerInfo())
	case "version":
		fmt.Print(dockerVersion())
	case "stats":
		fmt.Print(dockerStats())
	case "start":
		if len(args) < 2 {
			fmt.Println("Usage: dd start [container]")
			return
		}
		fmt.Print(execDockerCommand("start", args[1]))
	case "stop":
		if len(args) < 2 {
			fmt.Println("Usage: dd stop [container]")
			return
		}
		fmt.Print(execDockerCommand("stop", args[1]))
	case "restart":
		if len(args) < 2 {
			fmt.Println("Usage: dd restart [container]")
			return
		}
		fmt.Print(execDockerCommand("restart", args[1]))
	case "rm":
		if len(args) < 2 {
			fmt.Println("Usage: dd rm [container]")
			return
		}
		fmt.Print(execDockerCommand("rm", args[1]))
	case "rmi":
		if len(args) < 2 {
			fmt.Println("Usage: dd rmi [image]")
			return
		}
		fmt.Print(execDockerCommand("rmi", args[1]))
	case "logs":
		if len(args) < 2 {
			fmt.Println("Usage: dd logs [container]")
			return
		}
		if err := execDockerCommandWithError("logs", args[1]); err != nil {
			fmt.Printf("Error: %v\n", err)
		}
	case "exec":
		if len(args) < 3 {
			fmt.Println("Usage: dd exec [container] [command]")
			return
		}
		// For exec command, we need to handle interactive mode properly
		container := args[1]
		command := strings.Join(args[2:], " ")
		if err := execDockerCommandWithError("exec", "-it", container, "sh", "-c", command); err != nil {
			fmt.Printf("Error: %v\n", err)
		}
	case "run":
		if len(args) < 2 {
			fmt.Println("Usage: dd run [image] [args]")
			return
		}
		image := args[1]
		runArgs := []string{"run", "-it", image}
		if len(args) > 2 {
			runArgs = append(runArgs, args[2:]...)
		}
		if err := execDockerCommandWithError(runArgs...); err != nil {
			fmt.Printf("Error: %v\n", err)
		}
	case "pull":
		if len(args) < 2 {
			fmt.Println("Usage: dd pull [image]")
			return
		}
		fmt.Print(execDockerCommand("pull", args[1]))
	case "build":
		context := "."
		if len(args) > 1 {
			context = args[1]
		}
		if err := execDockerCommandWithError("build", context); err != nil {
			fmt.Printf("Error: %v\n", err)
		}
	default:
		// Execute the command directly if not a shortcut
		fmt.Print(execDockerCommand(args...))
	}
}