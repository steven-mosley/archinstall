.PHONY: test clean install

test:
	cd tests && bats .

check-syntax:
	shellcheck install.sh modules/*.sh tests/*.bats

clean:
	rm -f /var/log/archinstall.log
	rm -rf /tmp/archinstall-*

install:
	@echo "Installing archinstall dependencies..."
	pacman -S --needed --noconfirm bats shellcheck

.PHONY: help
help:
	@echo "Archinstall Makefile"
	@echo "Usage:"
	@echo "  make test         Run the test suite"
	@echo "  make check-syntax Check shell script syntax"
	@echo "  make clean        Clean temporary files"
	@echo "  make install      Install development dependencies"
