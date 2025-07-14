# PostgreSQL Environment Analyzer (Ruby)

This is a modular Ruby script designed to analyze a server's environment (macOS or Ubuntu) and generate recommended configurations for `postgresql.conf`, in addition to preparing the environment for `pg_badger` usage.

## Features
1.  Checks PostgreSQL version.
2.  Detects disk type (SSD/HDD).
3.  Retrieves RAM and Swap memory information.
4.  Identifies CPU core count.
5.  Provides instructions for `pg_badger` installation and usage.
6.  Generates recommended `postgresql.conf` settings based on the detected environment.

## Project Structure
-   `main_script.rb`: The main entry point of the script.
-   `lib/`: Directory containing helper modules:
    -   `system_info.rb`: Collects operating system information.
    -   `postgresql_config.rb`: Generates recommendations for `postgresql.conf`.
    -   `pg_badger_setup.rb`: Provides guidance on `pg_badger` setup.

## How to Use
1.  Clone the repository (or download the files):
    ```bash
    git clone <YOUR_REPOSITORY_URL>
    cd postgresql-env-analyzer-ruby
    ```
2.  Execute the script:
    ```bash
    ruby main_script.rb
    ```

## Requirements
-   **Ruby** (version 2.5 or higher recommended)
-   **System commands** (`psql`, `sysctl`, `lsblk`, `cat /proc/meminfo`, `nproc`, `system_profiler`) accessible in your system's PATH.
-   For Linux, the **`json` gem** (usually included with standard Ruby).

## Important Notes
* **Permissions:** The script executes system commands. Ensure the user running the script has the appropriate permissions.
* **Recommendations:** The generated `postgresql.conf` settings are **suggestions based on heuristics**. They **must always be reviewed and adjusted by an experienced DBA** for your specific environment and workload.
* **`pg_badger`:** The script only informs about the need for installation and configuration. `pg_badger` installation and execution are manual processes.
* **PostgreSQL Restart:** Many changes in `postgresql.conf` require the PostgreSQL service to be **restarted** for the new configurations to take effect.

## Contributions
Contributions are welcome! Feel free to open issues or pull requests.
