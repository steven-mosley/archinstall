import os
import subprocess
import curses

def check_dependencies():
    dependencies = ["lsblk", "mkfs.ext4", "pacstrap"]
    missing_deps = []

    for dep in dependencies:
        result = subprocess.run(["which", dep], capture_output=True, text=True)
        if result.returncode != 0:
            missing_deps.append(dep)

    if missing_deps:
        print("Missing dependencies: ", ", ".join(missing_deps))
        print("Please install the missing dependencies and try again.")
        exit(1)

def start_welcome_screen(stdscr):
    # Clear screen
    stdscr.clear()

    # Get screen height and width
    height, width = stdscr.getmaxyx()

    # Display welcome message
    welcome_message = "Welcome to the Arch Installer"
    x_position = width // 2 - len(welcome_message) // 2
    y_position = height // 2

    stdscr.addstr(y_position, x_position, welcome_message)
    stdscr.refresh()

    # Wait for user input before exiting welcome screen
    stdscr.getch()

def main():
    # Check if required dependencies are installed
    check_dependencies()

    # Start TUI using curses
    curses.wrapper(start_welcome_screen)

if __name__ == "__main__":
    main()
