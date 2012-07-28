opacmo
======

![opacmo logo](https://github.com/joejimbo/opacmo/raw/master/html/images/opacmo160.png)

[opacmo](http://www.opacmo.org) is the Open Access Mortar — a mash-up of biomedical objects linked to the open-access subset of PubMed Central.

* opacmo is an [interactive web-site](http://www.opacmo.org)
* opacmo is a web-service with JSON, SPARQL, etc., interfaces powered by [Yoctogi](http://www.yoctogi.org)
* opacmo is a generic text-mining pipeline that runs on single machines as well as [Oracle Grid Engine](http://en.wikipedia.org/wiki/Oracle_Grid_Engine) clusters.

Text-Mining 
-----------

### Running on a Desktop Computer

Text-mining the complete open access subset of PubMed Central can take a while on a single machine, but it can be done. Supported operating systems are Mac OS X and Linux.

    mkdir opacmo_release ; cd opacmo_release
    git clone git://github.com/joejimbo/opacmo.git
    git clone git://github.com/joejimbo/bioknack.git
    opacmo/make_opacmo.sh all 2>&1 | tee MAKE_OPACMO_LOG

### Running on a Oracle Grid Engine Cluster

Prepare a 'bundle' on a cluster node with internet access or your desktop computer, which can later be extracted and executed on a [Oracle Grid Engine](http://en.wikipedia.org/wiki/Oracle_Grid_Engine) (former Sun Grid Engine) cluster.

    mkdir opacmo_release ; cd opacmo_release
    git clone git://github.com/joejimbo/opacmo.git
    git clone git://github.com/joejimbo/bioknack.git
    opacmo/make_opacmo.sh bundle 2>&1 | tee MAKE_OPACMO_BUNDLE_LOG

Bundling can take a very long time, because it involves downloading all open access publications of PubMed Central, downloading several biomedical databases/ontologies, and preprocessing the latter for the text-mining run. The bundle itself will be quite large too (&gt;25G).

Now transfer the bundle to the cluster, log-in to the cluster, extract the bundle and continue the processing on the cluster. It is important that the chosen path below is accessible (read/write) to all cluster nodes, which is usually the case with your home directory on the cluster or a designated shared mount point.

    scp bundle.tar username@nodeX.yourdomain:/path/opacmo_release
    ssh username@nodeX.yourdomain
    cd /path/opacmo_release
    tar xf bundle.tar
    screen -DR opacmo_release
    opacmo/make_opacmo.sh sge 2>&1 | tee MAKE_OPACMO_CLUSTER_LOG

Running `opacmo/make_opacmo.sh sge` requires up to 8GB memory for postprocessing tasks. It might be necessary to request this amount of memory explicitly on your cluster by logging in to a node with `qrsh -l h_vmem=8G`.

Specific output of grid engine jobs is written into the respective `fork_*` directories as `opacmo.*.{e,o}*`. The actual text-mining output is written into the directory `opacmo_data`.

### Running on Amazon Elastic Compute Cloud

_Provisional_

    wget 'http://s3.amazonaws.com/ec2-downloads/ec2-api-tools.zip'
    unzip ec2-api-tools.zip

#### Java Installation on Mac OS X

    /usr/bin/java

A dialogue will pop-up for installing Java Runtime Environment.

    export JAVA_HOME="/System/Library/Java/JavaVirtualMachines/`ls /System/Library/Java/JavaVirtualMachines | grep '.jdk' | tail -n 1`"

Database & Web-Server Set-Up
----------------------------

### PostgreSQL

Install PostgreSQL 8.3 or newer, then -- on a Debian distro -- do

    sudo su - postgres
    createuser yoctogi
    Shall the new role be a superuser? (y/n) n
    Shall the new role be allowed to create databases? (y/n) n
    Shall the new role be allowed to create more new roles? (y/n) n
    createdb yoctogi
    load_opacmo.sh
    psql yoctogi
    ALTER USER yoctogi WITH PASSWORD 'yoctogi';
    GRANT SELECT ON yoctogi TO yoctogi;
    ^D


The `load_opacmo.sh` command expects the Yoctogi TSV files that have been generated in the directory `./opacmo_data`.

### lighttpd

Install and set up lighttpd. opacmo uses Yoctogi as backend, which requires FastCGI support.

    sudo apt-get install libfcgi-dev
    sudo gem install ruby-fcgi

### Workarounds

On Debian 5.0 you have to cheat a little bit to get the FastCGI going.

    cd /usr/include
    sudo ln -s ruby-1.9.0 ruby-1.9.1

Acknowledgements
----------------

Contributors in alphabetical order:

* Kenneth Chu. *Beta Testing.*
* Miyuki Fukuma. *Web-Design Consulting & CSS Coding.*

Licenses
--------

opacmo's source code is licensed under the [MIT License](https://raw.github.com/joejimbo/opacmo/master/LICENSE). opacmo's art work is licensed under the Creative Commons [Attribution-NonCommercial-NoDerivs 3.0](http://creativecommons.org/licenses/by-nc-nd/3.0/) license.

The PNG-files in

* `html/images/blue`
* `html/images/cyan`
* `html/images/grey_light`
* `html/images/red`

are part of the [Iconic](http://somerandomdude.com/projects/iconic/) minimal set of icons by
P.J. Onori. These icons are licenced under the
Creative Commons [Attribution-ShareAlike 3.0 United States](http://creativecommons.org/licenses/by-sa/3.0/us/)
license.

The spinner image `html/images/ajax-loader.gif` was created by [ajaxload.info](http://www.ajaxload.info/).
