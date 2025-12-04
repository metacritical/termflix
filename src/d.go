package main

import (
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"
)

const (
	ColorReset  = "\033[0m"
	ColorRed    = "\033[31m"
	ColorGreen  = "\033[32m"
	ColorYellow = "\033[33m"
	ColorBlue   = "\033[34m"
	ColorPurple = "\033[35m"
	ColorCyan   = "\033[36m"
	ColorWhite  = "\033[37m"
	Bold        = "\033[1m"
	Dim         = "\033[2m"
	Underline   = "\033[4m"
)

// execDockerCommand executes docker commands and returns their full output as a string.
// Use this for commands where the program needs to parse the output (e.g. listings).
func execDockerCommand(args ...string) string {
    cmd := exec.Command("docker", args...)
    output, _ := cmd.CombinedOutput()
    return string(output)
}

// execDockerCommandWithError executes docker commands streaming output directly to the terminal.
// Use this for interactive/long-running commands where the user should see output live.
func execDockerCommandWithError(args ...string) error {
    cmd := exec.Command("docker", args...)
    cmd.Stdout = os.Stdout
    cmd.Stderr = os.Stderr
    cmd.Stdin = os.Stdin
    return cmd.Run()
}

// execDocker is a convenience alias for streaming docker output to the terminal.
func execDocker(args ...string) error { return execDockerCommandWithError(args...) }

// parseNumberRanges converts string ranges like "1-3,5,7" into a slice of numbers
func parseNumberRanges(input string) ([]int, error) {
	var result []int
	parts := strings.Split(input, ",")

	for _, part := range parts {
		part = strings.TrimSpace(part)
		if strings.Contains(part, "-") {
			// Handle range like "1-3"
			rangeParts := strings.Split(part, "-")
			if len(rangeParts) != 2 {
				continue
			}
			start, err1 := strconv.Atoi(rangeParts[0])
			end, err2 := strconv.Atoi(rangeParts[1])
			if err1 != nil || err2 != nil {
				continue
			}
			for i := start; i <= end; i++ {
				result = append(result, i)
			}
		} else {
			// Handle single number
			num, err := strconv.Atoi(part)
			if err != nil {
				continue
			}
			result = append(result, num)
		}
	}
	return result, nil
}

// formatContainersForSCMBreeze formats containers similar to SCM Breeze
func formatContainersForSCMBreeze(containers []string) string {
	if len(containers) == 0 {
		return ColorRed + "No containers found\n" + ColorReset
	}

	// Parse all containers first to calculate column widths
	var parsedContainers [][]string
	for _, container := range containers {
		fields := strings.Split(strings.TrimSpace(container), "\t")
		// Ensure we have at least 4 fields (ID, Name, Status, Ports)
		// If ports is empty, we still want to include the container
		if len(fields) >= 3 {
			// Pad with empty string if ports field is missing
			if len(fields) == 3 {
				fields = append(fields, "") // Add empty ports field
			}
			if len(fields) >= 4 {
				parsedContainers = append(parsedContainers, fields)
			}
		}
	}

	if len(parsedContainers) == 0 {
		return ColorRed + "No containers found\n" + ColorReset
	}

	// Calculate max width for each column (excluding ports which will be formatted separately)
	maxNumWidth := len(fmt.Sprintf("%d", len(parsedContainers)))
	maxIdWidth := 10   // minimum width for ID column
	maxNameWidth := 15 // minimum width for NAMES column
	maxStatusWidth := 15 // minimum width for STATUS column

	for _, fields := range parsedContainers {
		if len(fields) >= 4 {
			if len(fields[0]) > maxIdWidth {
				maxIdWidth = len(fields[0])
			}
			if len(fields[1]) > maxNameWidth {
				maxNameWidth = len(fields[1])
			}
			if len(fields[2]) > maxStatusWidth {
				maxStatusWidth = len(fields[2])
			}
		}
	}

	// Add some padding to column widths
	maxIdWidth += 2
	maxNameWidth += 2
	maxStatusWidth += 2

	var output strings.Builder
	output.WriteString(fmt.Sprintf(ColorBlue+"# Docker Containers (%d found)\n"+ColorReset, len(parsedContainers)))
	output.WriteString(ColorYellow + "# Use: d c rm 1 2 3  or  d c rm 1-3 to select containers by number\n" + ColorReset)
	output.WriteString("#\n")
	
	// Build header with calculated widths (use a reasonable default for ports width)
	header := fmt.Sprintf("#   %sNUM %-*s %-*s %-*s %s%s\n", 
		ColorCyan, 
		maxIdWidth, "ID", 
		maxNameWidth, "NAMES", 
		maxStatusWidth, "STATUS", 
		"PORTS",
		ColorReset)
	output.WriteString(header)
	
	// Build separator with calculated widths
	separator := fmt.Sprintf("#   %s--- %-*s %-*s %-*s %s%s\n", 
		ColorCyan,
		maxIdWidth, strings.Repeat("-", maxIdWidth), 
		maxNameWidth, strings.Repeat("-", maxNameWidth), 
		maxStatusWidth, strings.Repeat("-", maxStatusWidth), 
		strings.Repeat("-", 30), // Use reasonable default for ports
		ColorReset)
	output.WriteString(separator)

	// Output each container with proper column alignment
	for i, fields := range parsedContainers {
		if len(fields) >= 4 {
			// Format ports as multi-line if there are multiple ports
			portsLines := formatPortsMultiline(fields[3])
			
			for j, portLine := range portsLines {
				if j == 0 {
					// First line includes all columns
					alignedPortLine := addIPv6Indicator(portLine)
					output.WriteString(fmt.Sprintf("#   "+ColorGreen+"[%*d]"+ColorReset+" %-*s %-*s %-*s %s\n", 
						maxNumWidth, i+1, 
						maxIdWidth, fields[0], 
						maxNameWidth, fields[1], 
						maxStatusWidth, fields[2], 
						alignedPortLine))
				} else {
					// Subsequent lines have empty space for other columns
					alignedPortLine := addIPv6Indicator(portLine)
					// Calculate exact spacing for alignment - need to count chars from beginning
					output.WriteString(fmt.Sprintf("#   %*s   %-*s %-*s %-*s %s\n", 
						maxNumWidth, "", 
						maxIdWidth, "", 
						maxNameWidth, "", 
						maxStatusWidth, "", 
						alignedPortLine))
				}
			}
		}
	}

	return output.String()
}

// formatImagesForSCMBreeze formats images similar to SCM Breeze
func formatImagesForSCMBreeze(images []string) string {
	if len(images) == 0 {
		return ColorRed + "No images found\n" + ColorReset
	}

	// Parse all images first to calculate column widths
	var parsedImages [][]string
	for _, image := range images {
		fields := strings.Split(strings.TrimSpace(image), "\t")
		if len(fields) >= 4 {
			parsedImages = append(parsedImages, fields)
		}
	}

	if len(parsedImages) == 0 {
		return ColorRed + "No images found\n" + ColorReset
	}

	// Calculate max width for each column
	maxNumWidth := len(fmt.Sprintf("%d", len(parsedImages)))
	maxRepoWidth := 12 // minimum width for repository column
	maxTagWidth := 8   // minimum width for tag column
	maxIdWidth := 12   // minimum width for ID column
	maxSizeWidth := 8  // minimum width for size column

	for _, fields := range parsedImages {
		if len(fields) >= 4 {
			if len(fields[0]) > maxRepoWidth {
				maxRepoWidth = len(fields[0])
			}
			if len(fields[1]) > maxTagWidth {
				maxTagWidth = len(fields[1])
			}
			if len(fields[2]) > maxIdWidth {
				maxIdWidth = len(fields[2])
			}
			if len(fields[3]) > maxSizeWidth {
				maxSizeWidth = len(fields[3])
			}
		}
	}

	// Add some padding to column widths
	maxRepoWidth += 2
	maxTagWidth += 2
	maxIdWidth += 2
	maxSizeWidth += 2

	var output strings.Builder
	output.WriteString(fmt.Sprintf(ColorBlue+"# Docker Images (%d found)\n"+ColorReset, len(parsedImages)))
	output.WriteString(ColorYellow + "# Use: d rm 1 2 3  or  d rm 1-3 to select images by number\n" + ColorReset)
	output.WriteString("#\n")
	
	// Build header with calculated widths
	header := fmt.Sprintf("#   %sNUM %-*s %-*s %-*s %-*s%s\n", 
		ColorCyan, 
		maxRepoWidth, "REPOSITORY", 
		maxTagWidth, "TAG", 
		maxIdWidth, "ID", 
		maxSizeWidth, "SIZE",
		ColorReset)
	output.WriteString(header)
	
	// Build separator with calculated widths
	separator := fmt.Sprintf("#   %s--- %-*s %-*s %-*s %-*s%s\n", 
		ColorCyan,
		maxRepoWidth, strings.Repeat("-", maxRepoWidth), 
		maxTagWidth, strings.Repeat("-", maxTagWidth), 
		maxIdWidth, strings.Repeat("-", maxIdWidth), 
		maxSizeWidth, strings.Repeat("-", maxSizeWidth),
		ColorReset)
	output.WriteString(separator)

	// Output each image with proper column alignment
	for i, fields := range parsedImages {
		if len(fields) >= 4 {
			output.WriteString(fmt.Sprintf("#   "+ColorGreen+"[%*d]"+ColorReset+" %-*s %-*s %-*s %-*s\n", 
				maxNumWidth, i+1, 
				maxRepoWidth, fields[0], 
				maxTagWidth, fields[1], 
				maxIdWidth, fields[2], 
				maxSizeWidth, fields[3]))
		}
	}

	return output.String()
}

// formatVolumesForSCMBreeze formats volumes similar to SCM Breeze
func formatVolumesForSCMBreeze(volumes []string) string {
	if len(volumes) == 0 {
		return ColorRed + "No volumes found\n" + ColorReset
	}

	// Parse all volumes first to calculate column widths
	var parsedVolumes [][]string
	for _, volume := range volumes {
		fields := strings.Split(strings.TrimSpace(volume), "\t")
		if len(fields) >= 2 {
			parsedVolumes = append(parsedVolumes, fields)
		}
	}

	if len(parsedVolumes) == 0 {
		return ColorRed + "No volumes found\n" + ColorReset
	}

	// Calculate max width for each column
	maxNumWidth := len(fmt.Sprintf("%d", len(parsedVolumes)))
	maxDriverWidth := 10 // minimum width for DRIVER column
	maxNameWidth := 15   // minimum width for NAME column

	for _, fields := range parsedVolumes {
		if len(fields) >= 2 {
			if len(fields[0]) > maxDriverWidth {
				maxDriverWidth = len(fields[0])
			}
			if len(fields[1]) > maxNameWidth {
				maxNameWidth = len(fields[1])
			}
		}
	}

	// Add some padding to column widths
	maxDriverWidth += 2
	maxNameWidth += 2

	var output strings.Builder
	output.WriteString(fmt.Sprintf(ColorBlue+"# Docker Volumes (%d found)\n"+ColorReset, len(parsedVolumes)))
	output.WriteString(ColorYellow + "# Use: d v rm 1 2 3  or  d v rm 1-3 to select volumes by number\n" + ColorReset)
	output.WriteString("#\n")
	
	// Build header with calculated widths
	header := fmt.Sprintf("#   %sNUM %-*s %-*s%s\n", 
		ColorCyan, 
		maxDriverWidth, "DRIVER", 
		maxNameWidth, "NAME",
		ColorReset)
	output.WriteString(header)
	
	// Build separator with calculated widths
	separator := fmt.Sprintf("#   %s--- %-*s %-*s%s\n", 
		ColorCyan,
		maxDriverWidth, strings.Repeat("-", maxDriverWidth), 
		maxNameWidth, strings.Repeat("-", maxNameWidth),
		ColorReset)
	output.WriteString(separator)

	// Output each volume with proper column alignment
	for i, fields := range parsedVolumes {
		if len(fields) >= 2 {
			output.WriteString(fmt.Sprintf("#   "+ColorGreen+"[%*d]"+ColorReset+" %-*s %-*s\n", 
				maxNumWidth, i+1, 
				maxDriverWidth, fields[0], 
				maxNameWidth, fields[1]))
		}
	}

	return output.String()
}

// formatNetworksForSCMBreeze formats networks similar to SCM Breeze
func formatNetworksForSCMBreeze(networks []string) string {
	if len(networks) == 0 {
		return ColorRed + "No networks found\n" + ColorReset
	}

	// Parse all networks first to calculate column widths
	var parsedNetworks [][]string
	for _, network := range networks {
		fields := strings.Split(strings.TrimSpace(network), "\t")
		if len(fields) >= 4 {
			parsedNetworks = append(parsedNetworks, fields)
		}
	}

	if len(parsedNetworks) == 0 {
		return ColorRed + "No networks found\n" + ColorReset
	}

	// Calculate max width for each column
	maxNumWidth := len(fmt.Sprintf("%d", len(parsedNetworks)))
	maxIdWidth := 10     // minimum width for ID column
	maxNameWidth := 15   // minimum width for NAME column
	maxDriverWidth := 10 // minimum width for DRIVER column
	maxScopeWidth := 8   // minimum width for SCOPE column

	for _, fields := range parsedNetworks {
		if len(fields) >= 4 {
			if len(fields[0]) > maxIdWidth {
				maxIdWidth = len(fields[0])
			}
			if len(fields[1]) > maxNameWidth {
				maxNameWidth = len(fields[1])
			}
			if len(fields[2]) > maxDriverWidth {
				maxDriverWidth = len(fields[2])
			}
			if len(fields[3]) > maxScopeWidth {
				maxScopeWidth = len(fields[3])
			}
		}
	}

	// Add some padding to column widths
	maxIdWidth += 2
	maxNameWidth += 2
	maxDriverWidth += 2
	maxScopeWidth += 2

	var output strings.Builder
	output.WriteString(fmt.Sprintf(ColorBlue+"# Docker Networks (%d found)\n"+ColorReset, len(parsedNetworks)))
	output.WriteString(ColorYellow + "# Use: d n rm 1 2 3  or  d n rm 1-3 to select networks by number\n" + ColorReset)
	output.WriteString("#\n")
	
	// Build header with calculated widths
	header := fmt.Sprintf("#   %sNUM %-*s %-*s %-*s %-*s%s\n", 
		ColorCyan, 
		maxIdWidth, "ID", 
		maxNameWidth, "NAME", 
		maxDriverWidth, "DRIVER", 
		maxScopeWidth, "SCOPE",
		ColorReset)
	output.WriteString(header)
	
	// Build separator with calculated widths
	separator := fmt.Sprintf("#   %s--- %-*s %-*s %-*s %-*s%s\n", 
		ColorCyan,
		maxIdWidth, strings.Repeat("-", maxIdWidth), 
		maxNameWidth, strings.Repeat("-", maxNameWidth), 
		maxDriverWidth, strings.Repeat("-", maxDriverWidth), 
		maxScopeWidth, strings.Repeat("-", maxScopeWidth),
		ColorReset)
	output.WriteString(separator)

	// Output each network with proper column alignment
	for i, fields := range parsedNetworks {
		if len(fields) >= 4 {
			output.WriteString(fmt.Sprintf("#   "+ColorGreen+"[%*d]"+ColorReset+" %-*s %-*s %-*s %-*s\n", 
				maxNumWidth, i+1, 
				maxIdWidth, fields[0], 
				maxNameWidth, fields[1], 
				maxDriverWidth, fields[2], 
				maxScopeWidth, fields[3]))
		}
	}

	return output.String()
}

// listRunningContainersSCM returns running containers in SCM Breeze format
func listRunningContainersSCM() string {
	output := execDockerCommand("ps", "--format", `{{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}`)
	lines := strings.Split(output, "\n")
	return formatContainersForSCMBreeze(lines)
}

// listAllContainersSCM returns all containers in SCM Breeze format
func listAllContainersSCM() string {
	output := execDockerCommand("ps", "-a", "--format", `{{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}`)
	lines := strings.Split(output, "\n")
	return formatContainersForSCMBreeze(lines)
}

// listImagesSCM returns images in SCM Breeze format
func listImagesSCM() string {
	output := execDockerCommand("images", "--format", `{{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}`)
	lines := strings.Split(output, "\n")
	return formatImagesForSCMBreeze(lines)
}

// listVolumesSCM returns volumes in SCM Breeze format
func listVolumesSCM() string {
	output := execDockerCommand("volume", "ls", "--format", `{{.Driver}}\t{{.Name}}`)
	lines := strings.Split(output, "\n")
	return formatVolumesForSCMBreeze(lines)
}

// listNetworksSCM returns networks in SCM Breeze format
func listNetworksSCM() string {
	output := execDockerCommand("network", "ls", "--format", `{{.ID}}\t{{.Name}}\t{{.Driver}}\t{{.Scope}}`)
	lines := strings.Split(output, "\n")
	return formatNetworksForSCMBreeze(lines)
}

// getContainerIDsFromLines gets container IDs based on selected line numbers
func getContainerIDsFromLines(lines []string, numbers []int) []string {
	var ids []string
	for _, num := range numbers {
		// Adjust for 1-based user input to 0-based array indexing
		index := num - 1
		if index >= 0 && index < len(lines) {
			fields := strings.Split(strings.TrimSpace(lines[index]), "\t")
			// Ensure we have at least 3 fields (ID, Name, Status) and add empty ports if needed
			if len(fields) >= 3 {
				// If we only have 3 fields (ID, Name, Status), and ports are missing, 
				// we still want to process this container
				if len(fields) == 3 {
					fields = append(fields, "") // Add empty ports field to make 4 total
				}
				if len(fields) >= 4 {
					ids = append(ids, fields[0]) // First field is container ID
				}
			}
		}
	}
	return ids
}

// getImageIDsFromLines gets image IDs based on selected line numbers
func getImageIDsFromLines(lines []string, numbers []int) []string {
	var ids []string
	for _, num := range numbers {
		// Adjust for 1-based user input to 0-based array indexing
		index := num - 1
		if index >= 0 && index < len(lines) {
			fields := strings.Split(strings.TrimSpace(lines[index]), "\t")
			if len(fields) >= 4 {
				ids = append(ids, fields[2]) // Third field (0-indexed) is image ID
			}
		}
	}
	return ids
}

// getVolumeNamesFromLines gets volume names based on selected line numbers
func getVolumeNamesFromLines(lines []string, numbers []int) []string {
	var names []string
	for _, num := range numbers {
		// Adjust for 1-based user input to 0-based array indexing
		index := num - 1
		if index >= 0 && index < len(lines) {
			fields := strings.Split(strings.TrimSpace(lines[index]), "\t")
			if len(fields) >= 2 {
				names = append(names, fields[1]) // Second field is volume name
			}
		}
	}
	return names
}

// getNetworkIDsFromLines gets network IDs based on selected line numbers
func getNetworkIDsFromLines(lines []string, numbers []int) []string {
	var ids []string
	for _, num := range numbers {
		// Adjust for 1-based user input to 0-based array indexing
		index := num - 1
		if index >= 0 && index < len(lines) {
			fields := strings.Split(strings.TrimSpace(lines[index]), "\t")
			if len(fields) >= 4 {
				ids = append(ids, fields[0]) // First field is network ID
			}
		}
	}
	return ids
}

func main() {
	args := os.Args[1:]

	if len(args) == 0 {
		fmt.Println(ColorBlue + Bold + "Docker utility - SCM Breeze style shortcuts for Docker commands" + ColorReset)
		fmt.Println()
		fmt.Println(ColorYellow + "Usage: d [command]" + ColorReset)
		fmt.Println(ColorYellow + "   or: d c [command]     (for container operations)" + ColorReset)
		fmt.Println(ColorYellow + "   or: d v [command]     (for volume operations)" + ColorReset)
		fmt.Println(ColorYellow + "   or: d n [command]     (for network operations)" + ColorReset)
		fmt.Println()
		fmt.Println(ColorCyan + "General commands:" + ColorReset)
		fmt.Println("  " + ColorGreen + "c" + ColorReset + "                     - List all containers (SCM Breeze style, alias for 'd ls')")
		fmt.Println("  " + ColorGreen + "cd <number>" + ColorReset + "           - Get shell (bash or sh) in container by number")
		fmt.Println("  " + ColorGreen + "ps" + ColorReset + "                    - List running containers (SCM Breeze style)")
		fmt.Println("  " + ColorGreen + "ls" + ColorReset + "                    - List all containers (SCM Breeze style)")
		fmt.Println("  " + ColorGreen + "i | img" + ColorReset + "               - List images (SCM Breeze style)")
		fmt.Println("  " + ColorGreen + "v | vol" + ColorReset + "               - List volumes (SCM Breeze style)")
		fmt.Println("  " + ColorGreen + "n | net" + ColorReset + "               - List networks (SCM Breeze style)")
		fmt.Println("  " + ColorGreen + "df" + ColorReset + "                    - Show disk usage")
		fmt.Println("  " + ColorGreen + "prune" + ColorReset + "                 - Remove unused data")
		fmt.Println("  " + ColorGreen + "info" + ColorReset + "                  - Show system info")
		fmt.Println("  " + ColorGreen + "version" + ColorReset + "               - Show version")
		fmt.Println("  " + ColorGreen + "stats" + ColorReset + "                 - Show resource usage")
		fmt.Println()
		fmt.Println(ColorCyan + "Docker Compose commands:" + ColorReset)
		fmt.Println("  " + ColorGreen + "u" + ColorReset + "                     - Docker Compose up")
		fmt.Println("  " + ColorGreen + "d" + ColorReset + "                     - Docker Compose down")
		fmt.Println("  " + ColorGreen + "l" + ColorReset + "                     - Docker Compose logs")
		fmt.Println("  " + ColorGreen + "compose [command]" + ColorReset + "     - Use Docker Compose directly (up, down, ps, logs)")


		fmt.Println()
		fmt.Println(ColorCyan + "Container commands (d c):" + ColorReset)
		fmt.Println("  " + ColorGreen + "ps" + ColorReset + "                    - List running containers")
		fmt.Println("  " + ColorGreen + "ls" + ColorReset + "                    - List all containers")
		fmt.Println("  " + ColorGreen + "start 1 2 3" + ColorReset + "           - Start containers by number")
		fmt.Println("  " + ColorGreen + "stop 1 2 3" + ColorReset + "            - Stop containers by number")
		fmt.Println("  " + ColorGreen + "restart 1 2 3" + ColorReset + "         - Restart containers by number")
		fmt.Println("  " + ColorGreen + "rm 1 2 3" + ColorReset + "              - Remove containers by number")
		fmt.Println("  " + ColorGreen + "logs 1" + ColorReset + "                - View logs for container by number")
		fmt.Println("  " + ColorGreen + "exec 1 [command]" + ColorReset + "      - Execute command in container by number")
		fmt.Println()
		fmt.Println(ColorCyan + "Image commands:" + ColorReset)
		fmt.Println("  " + ColorGreen + "rm 1 2 3" + ColorReset + "              - Remove images by number")
		fmt.Println()
		fmt.Println(ColorCyan + "Volume commands (d v):" + ColorReset)
		fmt.Println("  " + ColorGreen + "ls" + ColorReset + "                    - List volumes")
		fmt.Println("  " + ColorGreen + "rm 1 2 3" + ColorReset + "              - Remove volumes by number")
		fmt.Println()
		fmt.Println(ColorCyan + "Network commands (d n):" + ColorReset)
		fmt.Println("  " + ColorGreen + "ls" + ColorReset + "                    - List networks")
		fmt.Println("  " + ColorGreen + "rm 1 2 3" + ColorReset + "              - Remove networks by number")
		fmt.Println()
		return
	}

	// Handle subcommands - first check if we have 'c' for containers, 'v' for volumes, 'n' for networks, 'compose' for compose
	if len(args) >= 2 {
		switch args[0] {
		case "c": // Container operations
			containerSubcommand(args[1:])
			return
		case "v": // Volume operations
			volumeSubcommand(args[1:])
			return
		case "n": // Network operations
			networkSubcommand(args[1:])
			return
		case "compose": // Docker Compose operations
			composeSubcommand(args[1:])
			return
		}
	}
	
	// Handle 'd c' as an alias for 'd ls' (list all containers)
	if len(args) == 1 && args[0] == "c" {
		fmt.Print(listAllContainersSCM())
		return
	}
	
	// Handle 'd cd' to get bash shell in container by number
	if len(args) == 2 && args[0] == "cd" {
		containerNum, err := strconv.Atoi(args[1])
		if err != nil {
			fmt.Printf("Error: %v\n", err)
			return
		}
		
		// Get current containers
		output := execDockerCommand("ps", "-a", "--format", `{{.ID}}	{{.Names}}	{{.Status}}	{{.Ports}}`)
		lines := strings.Split(output, "\n")
		if len(lines) < 2 {
			fmt.Println("No containers found")
			return
		}
		
		// Get container ID
		containerIDs := getContainerIDsFromLines(lines, []int{containerNum})
		if len(containerIDs) == 0 {
			fmt.Println("No valid container number found")
			return
		}
		
		// Execute docker exec bash command, fallback to sh if bash fails
		// First try bash, then fallback to sh
		shellOptions := []string{"bash", "sh"}
		var shellExecuted bool
		
		for _, shell := range shellOptions {
			cmd := exec.Command("docker", "exec", "-it", containerIDs[0], shell)
			cmd.Stdout = os.Stdout
			cmd.Stderr = os.Stderr
			cmd.Stdin = os.Stdin
			err = cmd.Run()
			if err == nil {
				shellExecuted = true
				break // Success, exit the loop
			}
			// If this is bash and it failed, try sh next iteration
		}
		
		if !shellExecuted {
			fmt.Printf("Error executing shell in container: both bash and sh failed\n")
		}
		return
	}

	// Handle general Docker commands
	switch args[0] {
	case "ps":
		fmt.Print(listRunningContainersSCM())
	case "ls":
		fmt.Print(listAllContainersSCM())
	case "i", "img", "images":
		fmt.Print(listImagesSCM())
	case "v", "vol", "volumes":
		fmt.Print(listVolumesSCM())
	case "n", "net", "networks":
		fmt.Print(listNetworksSCM())
	case "df":
		if err := execDocker("system", "df"); err != nil { fmt.Printf("Error: %v\n", err) }
	case "prune":
		if err := execDocker("system", "prune", "-f"); err != nil { fmt.Printf("Error: %v\n", err) }
	case "info":
		if err := execDocker("info"); err != nil { fmt.Printf("Error: %v\n", err) }
	case "version":
		if err := execDocker("--version"); err != nil { fmt.Printf("Error: %v\n", err) }
	case "stats":
		if err := execDocker("stats", "--no-stream"); err != nil { fmt.Printf("Error: %v\n", err) }
	case "u": // Docker Compose up
		if err := execDocker("compose", "up"); err != nil { fmt.Printf("Error: %v\n", err) }
	case "d": // Docker Compose down (we'll need to be careful with this one)
		// Check if this is meant to be compose down or if there are other 'd' commands that take precedence
		if err := execDocker("compose", "down"); err != nil { fmt.Printf("Error: %v\n", err) }
	case "l": // Docker Compose logs
		if err := execDocker("compose", "logs"); err != nil { fmt.Printf("Error: %v\n", err) }
	case "rm": // For images by number
		if len(args) < 2 {
			fmt.Println("Usage: d rm [number range] (e.g., d rm 1 2 3 or d rm 1-3)")
			return
		}
		// Get current images
		output := execDockerCommand("images", "--format", `{{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}`)
		lines := strings.Split(output, "\n")
		if len(lines) < 2 {
			fmt.Println("No images found")
			return
		}
		
		// Parse number ranges
		var allNumbers []int
		for i := 1; i < len(args); i++ {
			numbers, err := parseNumberRanges(args[i])
			if err != nil {
				fmt.Printf("Error parsing number range: %v\n", err)
				return
			}
			allNumbers = append(allNumbers, numbers...)
		}
		
		// Get image IDs
		imageIDs := getImageIDsFromLines(lines, allNumbers)
		if len(imageIDs) == 0 {
			fmt.Println("No valid image numbers found")
			return
		}
		
		// Execute docker rmi command
		dockerArgs := []string{"rmi"}
		dockerArgs = append(dockerArgs, imageIDs...)
		if err := execDocker(dockerArgs...); err != nil { fmt.Printf("Error: %v\n", err) }
	default:
		// Execute the command directly and stream output
		if err := execDocker(args...); err != nil {
			fmt.Printf(ColorRed+"Error running docker: %v\n"+ColorReset, err)
		}
	}
}

func containerSubcommand(args []string) {
	switch args[0] {
	case "ps":
		fmt.Print(listRunningContainersSCM())
	case "ls":
		fmt.Print(listAllContainersSCM())
	case "start":
		if len(args) < 2 {
			fmt.Println("Usage: d c start [number range] (e.g., d c start 1 2 3 or d c start 1-3)")
			return
		}
		// Get current containers
		output := execDockerCommand("ps", "-a", "--format", `{{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}`)
		lines := strings.Split(output, "\n")
		if len(lines) < 2 {
			fmt.Println("No containers found")
			return
		}
		
		// Parse number ranges
		var allNumbers []int
		for i := 1; i < len(args); i++ {
			numbers, err := parseNumberRanges(args[i])
			if err != nil {
				fmt.Printf("Error parsing number range: %v\n", err)
				return
			}
			allNumbers = append(allNumbers, numbers...)
		}
		
		// Get container IDs
		containerIDs := getContainerIDsFromLines(lines, allNumbers)
		if len(containerIDs) == 0 {
			fmt.Println("No valid container numbers found")
			return
		}
		
		// Execute docker start command
		dockerArgs := []string{"start"}
		dockerArgs = append(dockerArgs, containerIDs...)
		if err := execDocker(dockerArgs...); err != nil { fmt.Printf("Error: %v\n", err) }
	case "stop":
		if len(args) < 2 {
			fmt.Println("Usage: d c stop [number range] (e.g., d c stop 1 2 3 or d c stop 1-3)")
			return
		}
		// Get current containers
		output := execDockerCommand("ps", "-a", "--format", `{{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}`)
		lines := strings.Split(output, "\n")
		if len(lines) < 2 {
			fmt.Println("No containers found")
			return
		}
		
		// Parse number ranges
		var allNumbers []int
		for i := 1; i < len(args); i++ {
			numbers, err := parseNumberRanges(args[i])
			if err != nil {
				fmt.Printf("Error parsing number range: %v\n", err)
				return
			}
			allNumbers = append(allNumbers, numbers...)
		}
		
		// Get container IDs
		containerIDs := getContainerIDsFromLines(lines, allNumbers)
		if len(containerIDs) == 0 {
			fmt.Println("No valid container numbers found")
			return
		}
		
		// Execute docker stop command
		dockerArgs := []string{"stop"}
		dockerArgs = append(dockerArgs, containerIDs...)
		if err := execDocker(dockerArgs...); err != nil { fmt.Printf("Error: %v\n", err) }
	case "restart":
		if len(args) < 2 {
			fmt.Println("Usage: d c restart [number range] (e.g., d c restart 1 2 3 or d c restart 1-3)")
			return
		}
		// Get current containers
		output := execDockerCommand("ps", "-a", "--format", `{{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}`)
		lines := strings.Split(output, "\n")
		if len(lines) < 2 {
			fmt.Println("No containers found")
			return
		}
		
		// Parse number ranges
		var allNumbers []int
		for i := 1; i < len(args); i++ {
			numbers, err := parseNumberRanges(args[i])
			if err != nil {
				fmt.Printf("Error parsing number range: %v\n", err)
				return
			}
			allNumbers = append(allNumbers, numbers...)
		}
		
		// Get container IDs
		containerIDs := getContainerIDsFromLines(lines, allNumbers)
		if len(containerIDs) == 0 {
			fmt.Println("No valid container numbers found")
			return
		}
		
		// Execute docker restart command
		dockerArgs := []string{"restart"}
		dockerArgs = append(dockerArgs, containerIDs...)
		if err := execDocker(dockerArgs...); err != nil { fmt.Printf("Error: %v\n", err) }
	case "rm":
		if len(args) < 2 {
			fmt.Println("Usage: d c rm [number range] (e.g., d c rm 1 2 3 or d c rm 1-3)")
			return
		}
		// Get current containers
		output := execDockerCommand("ps", "-a", "--format", `{{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}`)
		lines := strings.Split(output, "\n")
		if len(lines) < 2 {
			fmt.Println("No containers found")
			return
		}
		
		// Parse number ranges
		var allNumbers []int
		for i := 1; i < len(args); i++ {
			numbers, err := parseNumberRanges(args[i])
			if err != nil {
				fmt.Printf("Error parsing number range: %v\n", err)
				return
			}
			allNumbers = append(allNumbers, numbers...)
		}
		
		// Get container IDs
		containerIDs := getContainerIDsFromLines(lines, allNumbers)
		if len(containerIDs) == 0 {
			fmt.Println("No valid container numbers found")
			return
		}
		
		// Execute docker rm command
		dockerArgs := []string{"rm"}
		dockerArgs = append(dockerArgs, containerIDs...)
		if err := execDocker(dockerArgs...); err != nil { fmt.Printf("Error: %v\n", err) }
	case "logs":
		if len(args) < 2 {
			fmt.Println("Usage: d c logs [container number]")
			return
		}
		// Get current containers
		output := execDockerCommand("ps", "-a", "--format", `{{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}`)
		lines := strings.Split(output, "\n")
		if len(lines) < 2 {
			fmt.Println("No containers found")
			return
		}
		
		// Parse number
		containerNum, err := strconv.Atoi(args[1])
		if err != nil {
			fmt.Printf("Error parsing container number: %v\n", err)
			return
		}
		
		// Get container ID
		containerIDs := getContainerIDsFromLines(lines, []int{containerNum})
		if len(containerIDs) == 0 {
			fmt.Println("No valid container number found")
			return
		}
		
		// Execute docker logs command
		if err := execDockerCommandWithError("logs", containerIDs[0]); err != nil {
			fmt.Printf("Error: %v\n", err)
		}
	case "exec":
		if len(args) < 3 {
			fmt.Println("Usage: d c exec [container number] [command]")
			return
		}
		// Get current containers
		output := execDockerCommand("ps", "-a", "--format", `{{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}`)
		lines := strings.Split(output, "\n")
		if len(lines) < 2 {
			fmt.Println("No containers found")
			return
		}
		
		// Parse number
		containerNum, err := strconv.Atoi(args[1])
		if err != nil {
			fmt.Printf("Error parsing container number: %v\n", err)
			return
		}
		
		// Get container ID
		containerIDs := getContainerIDsFromLines(lines, []int{containerNum})
		if len(containerIDs) == 0 {
			fmt.Println("No valid container number found")
			return
		}
		
		// Execute docker exec command
		command := strings.Join(args[2:], " ")
		if err := execDockerCommandWithError("exec", "-it", containerIDs[0], "sh", "-c", command); err != nil {
			fmt.Printf("Error: %v\n", err)
		}
	default:
		fmt.Printf(ColorRed+"Unknown container command: %s\n"+ColorReset, args[0])
		fmt.Println("Run 'd c' for help")
	}
}

func volumeSubcommand(args []string) {
	switch args[0] {
	case "ls":
		fmt.Print(listVolumesSCM())
	case "rm":
		if len(args) < 2 {
			fmt.Println("Usage: d v rm [number range] (e.g., d v rm 1 2 3 or d v rm 1-3)")
			return
		}
		// Get current volumes
		output := execDockerCommand("volume", "ls", "--format", `{{.Driver}}\t{{.Name}}`)
		lines := strings.Split(output, "\n")
		if len(lines) < 2 {
			fmt.Println("No volumes found")
			return
		}
		
		// Parse number ranges
		var allNumbers []int
		for i := 1; i < len(args); i++ {
			numbers, err := parseNumberRanges(args[i])
			if err != nil {
				fmt.Printf("Error parsing number range: %v\n", err)
				return
			}
			allNumbers = append(allNumbers, numbers...)
		}
		
		// Get volume names
		volumeNames := getVolumeNamesFromLines(lines, allNumbers)
		if len(volumeNames) == 0 {
			fmt.Println("No valid volume numbers found")
			return
		}
		
		// Execute docker volume rm command
		dockerArgs := []string{"volume", "rm"}
		dockerArgs = append(dockerArgs, volumeNames...)
		if err := execDocker(dockerArgs...); err != nil { fmt.Printf("Error: %v\n", err) }
	default:
		fmt.Printf(ColorRed+"Unknown volume command: %s\n"+ColorReset, args[0])
		fmt.Println("Run 'd v' for help")
	}
}

func networkSubcommand(args []string) {
	switch args[0] {
	case "ls":
		fmt.Print(listNetworksSCM())
	case "rm":
		if len(args) < 2 {
			fmt.Println("Usage: d n rm [number range] (e.g., d n rm 1 2 3 or d n rm 1-3)")
			return
		}
		// Get current networks
		output := execDockerCommand("network", "ls", "--format", `{{.ID}}\t{{.Name}}\t{{.Driver}}\t{{.Scope}}`)
		lines := strings.Split(output, "\n")
		if len(lines) < 2 {
			fmt.Println("No networks found")
			return
		}
		
		// Parse number ranges
		var allNumbers []int
		for i := 1; i < len(args); i++ {
			numbers, err := parseNumberRanges(args[i])
			if err != nil {
				fmt.Printf("Error parsing number range: %v\n", err)
				return
			}
			allNumbers = append(allNumbers, numbers...)
		}
		
		// Get network IDs
		networkIDs := getNetworkIDsFromLines(lines, allNumbers)
		if len(networkIDs) == 0 {
			fmt.Println("No valid network numbers found")
			return
		}
		
		// Execute docker network rm command
		dockerArgs := []string{"network", "rm"}
		dockerArgs = append(dockerArgs, networkIDs...)
		if err := execDocker(dockerArgs...); err != nil { fmt.Printf("Error: %v\n", err) }
	default:
		fmt.Printf(ColorRed+"Unknown network command: %s\n"+ColorReset, args[0])
		fmt.Println("Run 'd n' for help")
	}
}
// formatPortsMultiline formats port information to be displayed as multiple lines
func formatPortsMultiline(portsString string) []string {
	if portsString == "" {
		return []string{""}
	}
	
	// Split by comma to separate individual port mappings
	portMappings := strings.Split(portsString, ", ")
	
	// Return each port mapping as a separate line
	var result []string
	for _, port := range portMappings {
		trimmedPort := strings.TrimSpace(port)
		if trimmedPort != "" {
			result = append(result, trimmedPort)
		}
	}
	
	if len(result) == 0 {
		return []string{""}
	}
	
	return result
}

// addIPv6Indicator adds coloring for IPv6 addresses
func addIPv6Indicator(portLine string) string {
	if strings.Contains(portLine, "[::]") {
		// Color the [::] part and add IPv6 indicator
		indicatedPort := strings.Replace(portLine, "[::]", ColorYellow+"[::]"+ColorReset+"(IPv6)", 1)
		return indicatedPort
	}
	return portLine
}

func composeSubcommand(args []string) {
	if len(args) == 0 {
		// Show compose help when just 'd compose' is run
		fmt.Println(ColorCyan + "Docker Compose commands:" + ColorReset)
		fmt.Println("  " + ColorGreen + "up" + ColorReset + "                    - Start services")
		fmt.Println("  " + ColorGreen + "down" + ColorReset + "                  - Stop and remove services")
		fmt.Println("  " + ColorGreen + "ps" + ColorReset + "                    - List services")
		fmt.Println("  " + ColorGreen + "logs" + ColorReset + "                  - View logs for services")
		return
	}
	
	switch args[0] {
	case "up":
		if err := execDocker("compose", "up"); err != nil { fmt.Printf("Error: %v\n", err) }
	case "down":
		if err := execDocker("compose", "down"); err != nil { fmt.Printf("Error: %v\n", err) }
	case "ps":
		if err := execDocker("compose", "ps"); err != nil { fmt.Printf("Error: %v\n", err) }
	case "logs":
		if err := execDocker("compose", "logs"); err != nil { fmt.Printf("Error: %v\n", err) }
	default:
		fmt.Printf(ColorRed+"Unknown compose command: %s\\n"+ColorReset, args[0])
		fmt.Println("Run 'd compose' for help")
	}
}
