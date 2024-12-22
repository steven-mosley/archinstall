import os
import subprocess
import curses


def list_disks():
    result = subprocess.run(["lsblk", "-dno", "NAME,SIZE"], stdout=subprocess.PIPE)
    disks = result.stdout.decode().strip().split("\n")
    return [disk.split() for disk in disks]


def partition_disk(disk, filesystem, encryption, subvolumes):
    # Partitioning logic here
    pass


def main(stdscr):
    curses.curs_set(0)
    stdscr.clear()

    disks = list_disks()
    current_row = 0

    while True:
        stdscr.clear()
        stdscr.addstr(0, 0, "Select a disk:")
        for idx, disk in enumerate(disks):
            if idx == current_row:
                stdscr.addstr(idx + 1, 0, f"> {disk[0]} ({disk[1]})", curses.A_REVERSE)
            else:
                stdscr.addstr(idx + 1, 0, f"  {disk[0]} ({disk[1]})")
        stdscr.refresh()

        key = stdscr.getch()
        if key == curses.KEY_UP and current_row > 0:
            current_row -= 1
        elif key == curses.KEY_DOWN and current_row < len(disks) - 1:
            current_row += 1
        elif key == curses.KEY_ENTER or key in [10, 13]:
            selected_disk = disks[current_row][0]
            break

    stdscr.clear()
    stdscr.addstr(0, 0, "Select filesystem:")
    filesystems = ["Btrfs", "Ext4"]
    current_row = 0

    while True:
        stdscr.clear()
        stdscr.addstr(0, 0, "Select filesystem:")
        for idx, fs in enumerate(filesystems):
            if idx == current_row:
                stdscr.addstr(idx + 1, 0, f"> {fs}", curses.A_REVERSE)
            else:
                stdscr.addstr(idx + 1, 0, f"  {fs}")
        stdscr.refresh()

        key = stdscr.getch()
        if key == curses.KEY_UP and current_row > 0:
            current_row -= 1
        elif key == curses.KEY_DOWN and current_row < len(filesystems) - 1:
            current_row += 1
        elif key == curses.KEY_ENTER or key in [10, 13]:
            selected_filesystem = filesystems[current_row]
            break

    stdscr.clear()
    stdscr.addstr(0, 0, "Enable encryption? (y/n):")
    stdscr.refresh()
    key = stdscr.getch()
    encryption = key in [ord("y"), ord("Y")]

    stdscr.clear()
    stdscr.addstr(
        0,
        0,
        "Enter custom subvolumes and mount points (comma separated, e.g., @home:/home,@var:/var):",
    )
    stdscr.refresh()
    curses.echo()
    subvolumes = stdscr.getstr(1, 0).decode().strip().split(",")

    partition_disk(selected_disk, selected_filesystem, encryption, subvolumes)


if __name__ == "__main__":
    curses.wrapper(main)
