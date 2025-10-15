#!/bin/bash

# Database connection info
DB_HOST="10.0.2.100"           # vip
DB_USER="sysbench"
DB_PASS="growin"
DB_NAME="sbtest"
TABLE_NAME="test_db"
COLUMN_NAME="id"
SYSTEM_TABLE_VALUE=0
INTERVAL_TIME=0.3



# check VIP status

ping ${DB_HOST} -c 1 
if [ $? -ge 1 ]; then 
    echo "Host ${DB_HOST} destination unreachable. Please check ${DB_HOST} first."
    echo "script aborting"
    exit 1;
else 
    echo "Host ${DB_HOST} ping check successful."
fi
 


# check if the database exists
DB_EXISTS=$(mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" -sse \
"SELECT COUNT(*) FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME='${DB_NAME}';")

if [ "${DB_EXISTS}" -eq 1 ]; then
    echo "DB already exists. Skipping DB create phase."
else
    echo "DB does not exist. Creating the ${DB_NAME} database."
    mysql -h "$DB_HOST" -u "$DB_USER" -p"${DB_PASS}" -e "create database ${DB_NAME}"
    echo "DB ${DB_NAME} created successful"
fi



# Check if the table exists
TABLE_EXISTS=$(mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -sse \
"SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = '$DB_NAME' AND table_name = '$TABLE_NAME';")

if [ "$TABLE_EXISTS" -eq 1 ]; then
    echo "Table exists. Retrieving the value of '$COLUMN_NAME' from the last row."

    # Extract value of specific column (from the last row)
    SYSTEM_TABLE_VALUE=$(mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -sse \
    "SELECT $COLUMN_NAME FROM $TABLE_NAME ORDER BY id DESC LIMIT 1;")
    let SYSTEM_TABLE_VALUE++

    echo "Extracted INDEX_VALUE: $HOSTNAME_VALUE"

    # Example usage
    if [ -n "$HOSTNAME_VALUE" ]; then
        echo "You can now use this value for further tasks, e.g., ping $HOSTNAME_VALUE"
    else
        echo "Column value is empty."
    fi
else
    echo "Table does not exist. Creating the table."

    mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -e "
    CREATE TABLE $TABLE_NAME (
        id INT PRIMARY KEY,
        created_at DATETIME DEFAULT NOW(),
        hostname VARCHAR(255)
    );"

    echo "Table created: $TABLE_NAME"
fi

echo "Test rows input starting ... "

while :
do
    mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" -e "INSERT INTO ${DB_NAME}.${TABLE_NAME} VALUES (${SYSTEM_TABLE_VALUE}, NOW(), @@HOSTNAME)";

    if [ $? -ge 1 ]; then
        sleep 3
    else
        let SYSTEM_TABLE_VALUE++
        sleep ${INTERVAL_TIME}
    fi

done

