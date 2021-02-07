#!/bin/sh
#
#	Basic POSIX psql/mysql migration framework
#
#	Copyright (c) 2020-2021, B.J.Scharp
#	https://www.bitwise-operators.com
#	All rights reserved.
#
#	Redistribution and use in source and binary forms, with or without
#	modification, are permitted provided that the following conditions are met:
#	* Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
#	* Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
#	* Neither the name of Bitwise Operators nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.
#	
#	THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#####	Set up environment
set -e
set -u
umask 077

#####	Begin function definitions
#	Print error to stderr
err() { 1>&2 echo "$*"; }

#	Print help message
print_help() {
	echo "Usage: $0 <command>"
	echo "where <command> is one of the following:"
	echo "	create <name>"
	echo "		Creates a new migration and rollback file, with format YYYYMMDDHHIISS_<name>.sql"
	echo "	list"
	echo "		Lists all currently installed migrations"
	echo "	migrate [<steps>|all]"
	echo "		Installs new migrations."
	echo "		If <steps> is numeric, will perform <steps> migrations"
	echo "		If 'all' is specified, will perform all available migrations"
	echo "		If nothing is specified, <steps> defaults to '1'"
	echo "	new"
	echo "		Shows all migrations waiting to be deployed"
	echo "	rollback [<steps>|all]"
	echo "		Similar to migrate, but will roll back the most recent migration(s)"
	echo "	help"
	echo "		Display this help message"
}

#	Prepare database connection
db_init() {
	#	mktemp is not POSIX, but common
	if command -v "mktemp" > /dev/null 2>&1 ; then 
		tmpfile=$(mktemp)
	else
		tmpfile=$(echo "mkstemp(format)" | m4 -D format="${TMPDIR:-/tmp}/tmp.XXXXXXXX")
	fi

	case $_DBTYPE in
		("psql")
			if [ -n "$_DBPASS" ]; then
				export PGPASSWORD="$_DBPASS"
			fi
			db_query "CREATE TABLE IF NOT EXISTS $_DBTABLE (id SERIAL PRIMARY KEY, name VARCHAR(255) NOT NULL, migrated TIMESTAMP NOT NULL DEFAULT NOW());" > /dev/null 2>&1
			;;
		("mysql")
			if [ -n "$_DBPASS" ]; then
				export MYSQL_PWD="$_DBPASS"
			fi
			db_query "CREATE TABLE IF NOT EXISTS $_DBTABLE (id INT AUTO_INCREMENT PRIMARY KEY, name VARCHAR(255) NOT NULL, migrated TIMESTAMP NOT NULL DEFAULT NOW());" > /dev/null 2>&1
			;;
		(*)
			err "Unknown database type"
			exit 1;;
	esac		
	db_query "SELECT name FROM $_DBTABLE ORDER BY name;" | awk '{$1=$1;print}' > "$tmpfile"
}

db_scripts() {
	while read -r script; do
		case $_DBTYPE in
			("psql")
				psql -h "$_DBHOST" -p "$_DBPORT" -U "$_DBUSER" -d "$_DBDB" -c "\set ON_ERROR_STOP TRUE" -f  "$1/$script"
				echo "$?"
				
			;;
			("mysql")
				mysql -h "$_DBHOST" -P "$_DBPORT" -u "$_DBUSER" -D "$_DBDB" < "$1/$script"
				echo "$?"
				;;
			(*)
				err "Unknown database type"
				exit 1;;
		esac
		if [ $1 = "migrations" ]; then
			db_query "INSERT INTO $_DBTABLE (name) VALUES ('$script');" > /dev/null 2>&1
			echo "Performed migration $script";	
		else
			db_query "DELETE FROM $_DBTABLE WHERE name='$script';" > /dev/null 2>&1
			echo "Rolled back migration $script";	
		fi
	done
}

db_query() {
	case $_DBTYPE in
		("psql")
			psql -h "$_DBHOST" -p "$_DBPORT" -U "$_DBUSER" -d "$_DBDB" -t -c "$1"
			;;
		("mysql")
			mysql -h "$_DBHOST" -P "$_DBPORT" -u "$_DBUSER" -D "$_DBDB" -B -N -e "$1"
			;;
		(*)
			err "Unknown database type"
			exit 1;;		
	esac
}

limit () {
	if [ ${steps:+x} ] && [ $steps != "all" ]; then
		head -n "$steps"
	else 
		cat -
	fi
}

cleanup () {
	if [ ${tmpfile:+x} ] && [ -f "$tmpfile" ]; then
		rm "$tmpfile"
	fi
}

#####	End function definitions

#	Check for config file
if [ -f "./config" ]; then
	. "./config"
else
	err "Config file not found"
	print_help;
	exit 1
fi

#	Check directories
if [ ! -d "${_DIRUP:=up}" ]; then
	err "Missing migration directory $_DIRUP"
	exit 1;
elif [ ! -d "${_DIRDOWN:=down}" ]; then
	err "Missing rollback directory $_DIRDOWN"
	exit 1;
fi


cmd=${1:-"empty"}
shift || true

steps=${1:-1}

if ! expr "$steps" : '^[[:digit:]]$' > /dev/null && ! expr "$steps" : '^all$' > /dev/null; then
	steps=1
fi

case $cmd in
	("create")
		if [ -z "$1" ]; then
			err "No name specfied"
			exit 1
		fi
		newname="$(date +%Y%m%d%H%M%S)_$1.sql"
		touch "$_DIRUP/$newname"
		touch "$_DIRDOWN/$newname"
		exit;;
	("list")
		db_init
		cat "$tmpfile"
		cleanup
		exit;;
	("migrate")
		db_init
		find "$_DIRUP" -type f -maxdepth 1 -name "*.sql" -exec basename {} \; | awk '{$1=$1;print}' | sort | comm -13 "$tmpfile" - | limit | db_scripts "$_DIRUP"
		cleanup
		exit;;		
	("new")
		db_init
		find "$_DIRUP" -type f -maxdepth 1 -name "*.sql" -exec basename {} \; | awk '{$1=$1;print}' | sort | comm -13 "$tmpfile" -
		cleanup
		exit;;			
	("rollback")
		db_init
		find "$_DIRDOWN" -type f -maxdepth 1 -name "*.sql" -exec basename {} \; | awk '{$1=$1;print}' | sort | comm -12 "$tmpfile" - | sort -r | limit | db_scripts "$_DIRDOWN"
		cleanup
		exit;;
	("help")
		#	Print help message and exit
		print_help
		exit;;
	(*)
		err "Invalid command or no command specified"
		print_help
		exit 1;;
esac
