# beget-scripts
Useful scripts for automating routine actions when working with hosting

# Examples of use

**beget-python-install.sh** - A script to automatically build the required version of Python 3 for use on Beget hosting, as well as installing Django or Flask

# Usage

### beget-python-install.sh

If you are using a hosting plan, you need to connect to the server via SSH, log into Docker, and then you can use the command to install Python 3 or Django or Flask:
```shell
wget -q 'https://raw.githubusercontent.com/welken23/beget-scripts/main/beget-python-install.sh' && chmod 700 beget-python-install.sh && ./beget-python-install.sh; rm beget-python-install.sh
```
