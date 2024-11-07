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

    dialog_win.addstr(1, (dialog_width - len(welcome_message)) // 2, welcome_message, curses.A_BOLD)
    dialog_win.addstr(3, 2, description_message)
    dialog_win.addstr(7, (dialog_width - len("[ OK ]")) // 2, "[ OK ]", curses.A_REVERSE)
    dialog_win.refresh()
    stdscr.refresh()

    # Wait for user to press enter
    while True:
        key = stdscr.getch()
        if key in [10, 13]:  # Enter key
            break

def partitioning_screen(stdscr):
    # Clear screen
    stdscr.clear()

    # Get screen height and width
    height, width = stdscr.getmaxyx()

    # Create a window for the partitioning dialog box
    dialog_height, dialog_width = 12, 60
    dialog_y = height // 2 - dialog_height // 2
    dialog_x = width // 2 - dialog_width // 2
    dialog_win = curses.newwin(dialog_height, dialog_width, dialog_y, dialog_x)
    textpad.rectangle(stdscr, dialog_y - 1, dialog_x - 1, dialog_y + dialog_height, dialog_x + dialog_width)

    # Display partitioning options
    title_message = "Partitioning Options"
    default_scheme_message = "1. Use default partition scheme (Btrfs)"
    custom_scheme_message = "2. Create a custom partition scheme"

    dialog_win.addstr(1, (dialog_width - len(title_message)) // 2, title_message, curses.A_BOLD)
    dialog_win.addstr(3, 2, default_scheme_message)
    dialog_win.addstr(4, 2, custom_scheme_message)
    dialog_win.addstr(10, (dialog_width - len("Select an option (1 or 2):")) // 2, "Select an option (1 or 2):")
    dialog_win.refresh()
    stdscr.refresh()

    # Wait for user input to select partitioning scheme
    while True:
        key = stdscr.getch()
        if key in [ord('1'), ord('2')]:
            selected_option = key
            break

    # Handle selection
    if selected_option == ord('1'):
        stdscr.addstr(height - 2, 2, "You selected the default partition scheme.", curses.A_BOLD)
        stdscr.addstr(height - 1, 2, "Default partition scheme:")
        stdscr.addstr(height, 2, " - @ mounted at /mnt")
        stdscr.addstr(height + 1, 2, " - @home mounted at /mnt/home")
        stdscr.addstr(height + 2, 2, " - @pkg mounted at /mnt/var/cache/pacman/pkg")
        stdscr.addstr(height + 3, 2, " - @log mounted at /mnt/var/log")
        stdscr.addstr(height + 4, 2, " - @snapshots mounted at /mnt/.snapshots")
        stdscr.refresh()
        stdscr.getch()
    elif selected_option == ord('2'):
        stdscr.addstr(height - 2, 2, "You selected to create a custom partition scheme.", curses.A_BOLD)
        stdscr.refresh()
        stdscr.getch()

def main():
    # Check if required dependencies are installed
    check_dependencies()

    # Start TUI using curses
    curses.wrapper(lambda stdscr: (start_welcome_screen(stdscr), partitioning_screen(stdscr)))

if __name__ == "__main__":
    main()
