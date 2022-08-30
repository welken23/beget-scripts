#!/usr/bin/env bash

env_check() {
  PORT=$(env|grep SSH_CONNECTION|awk '{print $NF}')
  if [[ "$PORT" != "222" ]]; then
    echo "To run this script, you need to log in to the Docker environment:" \
         "https://beget.com/ru/kb/how-to/web-apps/obshhie-svedeniya-po-ustanovke-prilozhenij-virtualnoe-okruzhenie-docker"
    exit 1
  fi
}

openssl_install() {
  if ! [ -d ~/.beget/tmp ]; then
    mkdir -p ~/.beget/tmp
  fi
  cd ~/.beget/tmp || { echo -e "\e[1;31mError! Failed to change the directory to ~/.beget/tmp\e[0m"; exit 1; }
  OPENSSL_VER=$(curl -sL https://www.openssl.org/source/ | grep -E 'openssl-1(.*)tar.gz' | awk -F'"' '{print $2}')
  OPENSSL_DIR=$(echo "$OPENSSL_VER" | awk -F'.tar' '{print $1}')
  wget -q "https://www.openssl.org/source/${OPENSSL_VER}"
  tar xvzf "$OPENSSL_VER" > /dev/null
  cd "$OPENSSL_DIR" || { echo -e "\e[1;31mError! Failed to change the directory to \$OPENSSL_DIR\e[0m"; exit 1; }
  sed -i 's#OPENSSLDIR "/certs"#"/etc/ssl/certs"#' include/internal/cryptlib.h
  if ! [ -d ~/.local ]; then
    mkdir -p ~/.local/ssl
    mkdir ~/.local/bin
  fi
  ./config --prefix="$HOME"/.local --openssldir="$HOME"/.local/ssl '-Wl,--enable-new-dtags,-rpath,$(LIBRPATH)' > /dev/null
  make -s -j33
  make install > /dev/null
  ~/.local/bin/openssl version
}

python_install() {
  if ! [ -d ~/.beget/tmp ]; then
    mkdir -p ~/.beget/tmp
  fi
  cd ~/.beget/tmp || { echo -e "\e[1;31mError! Failed to change the directory to ~/.beget/tmp\e[0m"; exit 1; }
  wget -q "https://www.python.org/ftp/python/${1}/Python-${1}.tgz"
  tar xvfz "Python-${1}.tgz" > /dev/null
  case ${1::-2} in
    3.10)  cd "Python-${1}" || { echo -e "\e[1;31mError! Failed to change the directory to Python-${1}\e[0m"; exit 1; }
           ./configure --prefix="$HOME"/.local --with-openssl="$HOME"/.local --with-openssl-rpath=auto > /dev/null
           make -s -j33
           make install > /dev/null
           ;;
    *)     wget -q 'ftp://sourceware.org/pub/libffi/libffi-3.2.1.tar.gz'
           tar -xf "libffi-3.2.1.tar.gz" > /dev/null
           cd "libffi-3.2.1" || { echo -e "\e[1;31mError! Failed to change the directory to libffi-3.2.1\e[0m"; exit 1; }
           if [ -d ~/.local/include/openssl ]; then
             rm -r ~/.local/include/openssl
           fi
           ./configure --prefix "$HOME"/.local LDFLAGS="-L/usr/local/lib" > /dev/null
           make -s -j33
           make install > /dev/null
           if ! [ -d ~/.local/include ]; then
             mkdir -p ~/.local/include
           fi
           cp x86_64-unknown-linux-gnu/include/ffi.h ~/.local/include
           cp x86_64-unknown-linux-gnu/include/ffitarget.h ~/.local/include
           cd "../Python-${1}" || { echo -e "\e[1;31mError! Failed to change the directory to ../Python-${1}\e[0m"; exit 1; }
           ./configure --prefix="$HOME"/.local --with-openssl=/usr/local LDFLAGS="-L/usr/local/lib" > /dev/null
           make -s -j33
           make install > /dev/null
           ;;
  esac
  ~/.local/bin/python"${1::-2}" -m pip install --upgrade pip
  ~/.local/bin/python"${1::-2}" -V
}

django_install() {
  echo -e "\e[1;32mPlease specify the path to the directory where you want to install Django. Input format: example.com (login.beget.tech, example.com, site.ru):\e[0m"
  read -r DPATH
  if ! [ -d "${HOME}/${DPATH}" ]; then
    mkdir "${HOME}/${DPATH}"
  fi
  cd "${HOME}/${DPATH}" || { echo -e "\e[1;31mError! Failed to change the directory to ~/\$DPATH\e[0m"; exit 1; }
  ~/.local/bin/pip"${1::-2}" install virtualenv
  ~/.local/bin/python"${1::-2}" -m virtualenv venv_django
  source venv_django/bin/activate
  case ${1::-2} in
    3.8|3.9|3.10)  pip3 install "django==4.0"
                   ;;
    *)             pip3 install django
                   ;;
  esac
  DATE=$(date +"%H%M_%d%m%y")
  echo -e "\e[1;32mPlease enter the Django project name. Input format: A word without spaces:\e[0m"
  read -r PROJECT
  django-admin startproject "$PROJECT"
  if ! [ -f passenger_wsgi.py ]; then
    touch passenger_wsgi.py
  else
    mv passenger_wsgi.py "passenger_wsgi_${DATE}.py"
    touch passenger_wsgi.py
  fi
  touch passenger_wsgi.py
  PPATH=$(realpath "$PROJECT")
  DFPATH=$(realpath venv_django/lib/python"${1::-2}"/site-packages)
  {
    echo "# -*- coding: utf-8 -*-"
    echo "import os, sys"
    echo "sys.path.insert(0, '$PPATH')"
    echo "sys.path.insert(1, '$DFPATH')"
    echo "os.environ['DJANGO_SETTINGS_MODULE'] = '$PROJECT.settings'"
    echo "from django.core.wsgi import get_wsgi_application"
    echo "application = get_wsgi_application()"
  } >> passenger_wsgi.py
  chmod 700 passenger_wsgi.py
  sed -i "s/ALLOWED_HOSTS = \[\]/ALLOWED_HOSTS = \['*'\]/" "${PROJECT}/${PROJECT}/settings.py"
  if ! [ -f .htaccess ]; then
    touch .htaccess
  else
    mv .htaccess ".htaccess_${DATE}"
    touch .htaccess
  fi
  {
    echo "PassengerEnabled On"
    echo "PassengerPython ${PWD}/venv_django/bin/python${1::-2}"
  } >> .htaccess
  chmod 700 .htaccess
  if ! [ -d public_html ]; then
    ln -s venv_django/lib/python"${1::-2}"/site-packages/django/contrib/admin public_html
  else
    mv public_html "public_html_${DATE}"
    ln -s venv_django/lib/python"${1::-2}"/site-packages/django/contrib/admin public_html
  fi
  mkdir tmp
  touch tmp/restart.txt
  echo -e "\e[1;32mFor security purposes, the server has installed a system of differentiation of access rights between sites, based on POSIX ACLs." \
       "This is done so that files from one site cannot access files from other sites. Applications to be installed in the '~/.local'" \
       "directories are, by default, unavailable when attempting to run them through the site. It is necessary to configure shared access" \
       "to these directories through the File Manager: https://sprutio.beget.com\n"
  echo -e "\e[1;32mWould you like to create a site administrator? Input format: y/n\e[0m"
  read -r ADM
  if [[ "$ADM" == "y" ]]; then
    echo -e "\e[1;32mEnter admin login:\e[0m"
    read -r ADMIN
    echo -e "\e[1;32mEnter the email address of the site administrator:\e[0m"
    read -r EMAIL
    python3 "${PROJECT}"/manage.py migrate
    python3 "${PROJECT}"/manage.py createsuperuser "--username=${ADMIN}" "--email=${EMAIL}"
  fi
}

flask_install() {
  echo -e "\e[1;32mPlease specify the path to the directory where you want to install Flask. Input format: example.com (login.beget.tech, example.com, site.ru):\e[0m"
  read -r FPATH
  if ! [ -d "${HOME}/${FPATH}" ]; then
    mkdir "${HOME}/${FPATH}"
  fi
  cd "${HOME}/${FPATH}" || { echo -e "\e[1;31mError! Failed to change the directory to ~/\$FPATH\e[0m"; exit 1; }
  ~/.local/bin/pip"${1::-2}" install virtualenv
  ~/.local/bin/python"${1::-2}" -m virtualenv venv_flask
  source venv_flask/bin/activate
  pip3 install flask
  DATE=$(date +"%H%M_%d%m%y")
  echo -e "\e[1;32mPlease enter the Flask project name. Input format: A word without spaces:\e[0m"
  read -r PROJECT
  mkdir "${PROJECT}"
  if ! [ -d  tmp ]; then
    mkdir tmp
  fi
  if ! [ -f .htaccess ]; then
    touch .htaccess
  else
    mv .htaccess ".htaccess_${DATE}"
    touch .htaccess
  fi
  {
    echo "PassengerEnabled On"
    echo "PassengerPython ${PWD}/venv_flask/bin/python${1::-2}"
  } >> .htaccess
  chmod 700 .htaccess
  if ! [ -f passenger_wsgi.py ]; then
    touch passenger_wsgi.py
  else
    mv passenger_wsgi.py "passenger_wsgi_${DATE}.py"
    touch passenger_wsgi.py
  fi
  {
    echo "# -*- coding: utf-8 -*-"
    echo "import os, sys"
    echo "sys.path.append('${PWD}/${PROJECT}')"
    echo "sys.path.append('${PWD}/venv_flask/lib/python${1::-2}/site-packages')"
    echo "from ${PROJECT} import app as application"
    echo "from werkzeug.debug import DebuggedApplication"
    echo "application.wsgi_app = DebuggedApplication(application.wsgi_app, True)"
    echo "application.debug = False"
  } >> passenger_wsgi.py
  chmod 700 passenger_wsgi.py
  if ! [ -f "${PROJECT}"/__init__.py ]; then
    touch "${PROJECT}"/__init__.py
  else
    mv "${PROJECT}"/__init__.py "${PROJECT}/__init__${DATE}.py"
    touch "${PROJECT}"/__init__.py
  fi
  {
    echo "from flask import Flask"
    echo -e "app = Flask(__name__)\n"
    echo "@app.route('/')"
    echo "def hello_world():"
    echo -e "  return 'Hello Flask!'\n"
    echo "if __name__ == '__main__':"
    echo -e "  app.run()"
  } >> "${PROJECT}"/__init__.py
  chmod 700 "${PROJECT}"/__init__.py
  touch tmp/restart.txt
  echo -e "\e[1;32mFor security purposes, the server has installed a system of differentiation of access rights between sites, based on POSIX ACLs." \
    "This is done so that files from one site cannot access files from other sites. Applications to be installed in the\e[0m \e[1;34m~/.local\e[0m" \
    "\e[1;32mdirectories are, by default, unavailable when attempting to run them through the site. It is necessary to configure shared access" \
    "to these directories through the File Manager:\e[0m \e[1;34mhttps://sprutio.beget.com\e[0m\n"
  echo -e "\e[1;32mDon't forget to create a symbolic link called public_html to the directory where the static files will be located.\e[0m\n" \
    "\e[1;32mThis can be done by using the command:\e[0m\n" \
    "\e[1;34m  ln -s ${HOME}/${FPATH}/path/to/static ${HOME}/${FPATH}/public_html\e[0m\n\n" \
    "\e[1;32mReplace the\e[0m \e[1;34m${HOME}/${FPATH}/path/to/static\e[0m \e[1;32mdirectory path with your\e[0m\n"
}

main() {
  env_check
  C_DIR="$PWD"
  echo -e "\e[1;32mWhich version of Python 3 would you like to install? Input format: 3.x.x (In the range from 3.6.0 to 3.10.x):\e[0m"
  read -r VERSION
  while true; do
    case ${VERSION::-2} in
      3.10)       openssl_install
                  python_install "$VERSION"
                  break
                  ;;
      3.[6789])   python_install "$VERSION"
                  break
                  ;;
      *)          echo -e "\e[1;32mEnter the correct version of Python 3. Input format: 3.x.x (3.8.2):\e[0m"
                  read -r VERSION
                  continue
                  ;;
    esac
  done
  rm -r ~/.beget/tmp/*
  cd ~ || { echo -e "\e[1;31mError! Failed to change the directory to ~\e[0m"; exit 1; }
  echo -e "\e[1;32mWould you like to install Django? Input format: y/n\e[0m"
  read -r DJANGO
  if [[ "$DJANGO" == "y" ]]; then
    django_install "$VERSION"
  fi
  echo -e "\e[1;32mWould you like to install Flask? Input format: y/n\e[0m"
  read -r FLASK
  if [[ "$FLASK" == "y" ]]; then
    flask_install "$VERSION"
  fi
  cd "$C_DIR" || { echo -e "\e[1;31mError! Failed to change the directory to \$C_DIR\e[0m"; exit 1; }
}

main
