import os
import subprocess
import curses
from curses import textpad

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

    # Create a window for the dialog box
    dialog_height, dialog_width = 10, 50
    dialog_y = height // 2 - dialog_height // 2
    dialog_x = width // 2 - dialog_width // 2
    dialog_win = curses.newwin(dialog_height, dialog_width, dialog_y, dialog_x)
    textpad.rectangle(stdscr, dialog_y - 1, dialog_x - 1, dialog_y + dialog_height, dialog_x + dialog_width)

    # Display welcome message in the dialog
    welcome_message = "Welcome to the Arch Linux Installer"
    description_message = "This installer will guide you through a minimal Arch Linux installation."

    dialog_win.addstr(1, (dialog_width - len(welcome_message)) // 2, welcome_message)
    dialog_win.addstr(3, 2, description_message)

    dialog_win.addstr(7, (dialog_width - len("Press any key to continue...")) // 2, "Press any key to continue...")
    dialog_win.refresh()
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

