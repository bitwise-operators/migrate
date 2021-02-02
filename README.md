# migrate
A simple posix-compliant shell script to facilitate database migrations for psql &amp; mysql

##	Usage
Create two directories called `migrations` and `rollbacks`. These will contain, respectively, the migrations and rollback scripts for your project. The migration script should be executed in the directory containing both.

Each migration in the `migrations` directory should be matched by an equally named rollback script in the `rollbacks` directory. You can easily create these using the supplied `create` command, which will timestamp the files for automatic sorting.

Each script should be a valid SQL script for the database you are using and have a filename ending in `.sql`

##	Configuration file
Rename the supplied `config.sample` file to `config` and edit it with the data required for your database. 
The following fields need to be set:

* _DBTYPE: The type of database to connect to. Supported values are psql and mysql
* _DBHOST: The ip or hostname the SQL server can be reached on
* _DBPORT: The port number the SQL server can be reached on (generally this is 5432 for psql and 3306 for mysql)
* _DBDB: The database to connect to
* _DBUSER: The user to connect as
* _DBPASS: The password to use when connecting. If you have set up password-less logins in your user account, or your database doesn't require a password, use an empty string
* _DBTABLE: The table used to keep track which migrations have been run. The script will create the table if needed.

## Commands
Usage: 

`./migrate.sh <command>`

where *&lt;command&gt;* is one of the following:

#### create &lt;name&gt; ####

Creates a new migration and rollback file, with format `YYYYMMDDHHIISS_<name>.sql`
	
#### list ####

Lists all currently installed migrations

#### migrate [&lt;steps&gt;| all ] ####

Installs new migrations.

If *&lt;steps&gt;* is numeric, will perform *&lt;steps&gt;* migrations

If 'all' is specified, will perform all available migrations

If nothing is specified, *&lt;steps&gt;* defaults to '1'

#### new ####

Shows all migrations waiting to be deployed
	
#### rollback [&lt;steps&gt;| all ] ####

Similar to migrate, but will roll back the most recent migration(s)
	
#### help ####

Display the help message

