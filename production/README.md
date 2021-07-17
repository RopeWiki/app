# RopeWiki server setup

Execute the following steps to produce a server running RopeWiki starting from a machine running Ubuntu.

1. Install necessary tools
    1. Update packages (`sudo apt-get update`)
    1. Install git (`sudo apt-get install git`)
    1. [Install docker](https://docs.docker.com/engine/install/ubuntu/#install-using-the-repository)
    1. Clone this repository into an appropriate folder (perhaps `/rw`)
1. Transfer site data
    1. ...from old server
        1. Create a folder that will hold persistent mount data (perhaps `/rw/mount`)
        1. Get latest SQL backup
            1. Create a subfolder in the persistent mount data folder that will hold SQL backups (perhaps `/rw/mount/sqlbackup`)
            1. Run `get_sql_backup.sh <SQL BACKUP FOLDER>`
        1. Get `images` folder
            1. Run `get_images.sh <ROPEWIKI MOUNT FOLDER>`
        
1. Deploy site
    1. Follow [the instructions to "Run a legacy server"](README.md#Run a legacy server)
