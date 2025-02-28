# Add utilities module with common helper functions

This commit introduces a new utilities module (`modules/utils.sh`) that provides
a collection of helper functions for the Arch Linux installer. These utilities
will help standardize common operations across the installation process.

Key features added:
- Colored logging functions with timestamps
- Debug logging with conditional output
- User input handling with default values
- Error handling and reporting
- Module loading functionality
- Process spinner for long-running tasks

This module establishes a consistent foundation for error handling, user
interaction, and logging throughout the installer, improving maintainability
and user experience.
