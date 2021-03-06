--  OSCAR Database Tables
--
--  This program is free software; you can redistribute it and/or modify
--  it under the terms of the GNU General Public License as published by
--  the Free Software Foundation; either version 2 of the License, or
--  (at your option) any later version.

--  This program is distributed in the hope that it will be useful,
--  but WITHOUT ANY WARRANTY; without even the implied warranty of
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--  GNU General Public License for more details.

--  You should have received a copy of the GNU General Public License
--  along with this program; if not, write to the Free Software
--  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307
--  USA

--
-- Copyright (c) 2006-2007 The Trustees of Indiana University.
--                    All rights reserved.
--
-- $Id: oscar_table.sql 9486 2012-10-29 09:56:50Z ol222822 $
--

--
-- All the OSCAR database tables are defined here and any changes on
-- this file will directly affect the OSCAR database implementation.
--

-- Clusters
CREATE TABLE IF NOT EXISTS Clusters(
    headnode_interface VARCHAR(100),
    id  integer   auto_increment not null unique,
    install_mode VARCHAR(100),
    installation_date  date,
    name VARCHAR(100)  not null unique,
    oscar_version VARCHAR(100),

    -- field that takes care of the multiple clusters: the "parent_id" represents the cluster id of the super oscar cluster if the oscar cluster is under the super oscar cluster.
    -- DEPRECATED??
    parent_id  integer  not null DEFAULT '1',
    server_architecture VARCHAR(100),
    server_distribution VARCHAR(100),
    server_distribution_version VARCHAR(100),
    PRIMARY KEY (id, parent_id),
    KEY parent_id ( parent_id ),
    CONSTRAINT Clusters_ibfk_1 FOREIGN KEY (parent_id) REFERENCES Clusters (id) ON DELETE CASCADE
)ENGINE=INNODB DEFAULT CHARSET=utf8;

-- Groups
CREATE TABLE IF NOT EXISTS Groups(
    id  integer   auto_increment not null unique primary key,
    name VARCHAR(100)  not null unique,
    selected  integer  DEFAULT '0',
    type VARCHAR(100)
)ENGINE=INNODB DEFAULT CHARSET=utf8;

-- Status
CREATE TABLE IF NOT EXISTS Status(
    id  integer auto_increment not null unique primary key,
    name VARCHAR(100)  not null unique
)ENGINE=INNODB DEFAULT CHARSET=utf8;

-- Package_status

CREATE TABLE IF NOT EXISTS Package_status(
	id integer auto_increment not null unique primary key,
	status VARCHAR(50)
)ENGINE=INNODB DEFAULT CHARSET=utf8;

-- Packages
CREATE TABLE IF NOT EXISTS Packages(
    id  integer   auto_increment not null unique primary key,
    package VARCHAR(100)    not null,
    version  VARCHAR(100)   not null,
    __class VARCHAR(100),
    __group VARCHAR(100),
    distro VARCHAR(32)   not null,
    summary VARCHAR(100),
    repository VARCHAR(250),
    license VARCHAR(100),
    maintainer VARCHAR(100),
    packager VARCHAR(250),
    url VARCHAR(100),
    vendor VARCHAR(100),
    description  text,
    KEY package ( package )
)ENGINE=INNODB DEFAULT CHARSET=utf8;

-- Images
CREATE TABLE IF NOT EXISTS Images(
    architecture VARCHAR(100),
    id  integer   auto_increment not null unique primary key,
    name VARCHAR(100)  not null unique,
    path VARCHAR(100)
)ENGINE=INNODB DEFAULT CHARSET=utf8;

-- Nodes
CREATE TABLE IF NOT EXISTS Nodes(
    cluster_id  integer not null default 0,
    cpu_num  integer,
    gpu_num  integer,
    cpu_speed VARCHAR(100),
    dns_domain VARCHAR(100),
    fqdn VARCHAR(100),
    group_name  VARCHAR(100),
    hostname VARCHAR(100),
    id  integer   auto_increment not null unique primary key,
    image_id  integer not null default 0,
    installer VARCHAR(100),
    name VARCHAR(100) not null,
    ram VARCHAR(100),
    swap VARCHAR(100),
    units VARCHAR(100),
    virtual VARCHAR(100),
    KEY cluster_id ( cluster_id ),
    KEY group_name ( group_name ),
    CONSTRAINT Nodes_ibfk_1 FOREIGN KEY (cluster_id) REFERENCES Clusters (id) ON DELETE CASCADE,
    CONSTRAINT Nodes_ibfk_2 FOREIGN KEY (group_name) REFERENCES Groups (name) ON DELETE CASCADE ON UPDATE CASCADE
)ENGINE=INNODB DEFAULT CHARSET=utf8;

-- OscarFileServer
CREATE TABLE IF NOT EXISTS OscarFileServer(
    oscar_httpd_pkg_cache VARCHAR(100),
    oscar_httpd_pkg_files VARCHAR(100),
    oscar_httpd_server_url VARCHAR(100)
);

-- Networks
CREATE TABLE IF NOT EXISTS Networks(
    base_ip VARCHAR(100),
    broadcast VARCHAR(100),
    cluster_id  integer,
    gateway VARCHAR(100),
    high_ip VARCHAR(100),
    n_id  integer   auto_increment not null unique primary key,
    name VARCHAR(100),
    netmask VARCHAR(100),
    rfc1918 VARCHAR(100),
    KEY cluster_id ( cluster_id ),
    CONSTRAINT Networks_ibfk_1 FOREIGN KEY (cluster_id) REFERENCES Clusters (id) ON DELETE CASCADE
)ENGINE=INNODB DEFAULT CHARSET=utf8;

-- Nics
CREATE TABLE IF NOT EXISTS Nics(
    id  integer   auto_increment not null unique primary key,
    ip VARCHAR(100),
    mac VARCHAR(100),
    name VARCHAR(100),
    network_id  integer,
    node_id  integer,
    KEY node_id ( node_id ),
    KEY network_id ( network_id ),
    CONSTRAINT Nics_ibfk_1 FOREIGN KEY (node_id) REFERENCES Nodes (id) ON DELETE CASCADE,
    CONSTRAINT Nics_ibfk_2 FOREIGN KEY (network_id) REFERENCES Networks (n_id) ON DELETE CASCADE
)ENGINE=INNODB DEFAULT CHARSET=utf8;

-- Packages_servicelists

CREATE TABLE IF NOT EXISTS Packages_servicelists(
    group_name VARCHAR(100),
    package  VARCHAR(100) not null,
    service VARCHAR(100) not null,
    PRIMARY KEY (package, service),
    KEY package ( package ),
    KEY group_name ( group_name ),
    CONSTRAINT Packages_servicelists_ibfk_1 FOREIGN KEY (package) REFERENCES Packages (package) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT Packages_servicelists_ibfk_2 FOREIGN KEY (group_name) REFERENCES Groups (name) ON DELETE CASCADE ON UPDATE CASCADE
)ENGINE=INNODB DEFAULT CHARSET=utf8;

-- Packages_switcher
CREATE TABLE IF NOT EXISTS Packages_switcher(
    package  VARCHAR(100) not null,
    switcher_name VARCHAR(100) not null,
    switcher_tag VARCHAR(100),
    PRIMARY KEY (package, switcher_name),
--    KEY package ( package ),
    CONSTRAINT Packages_switcher_ibfk_1 FOREIGN KEY (package) REFERENCES Packages (package) ON DELETE CASCADE ON UPDATE CASCADE
)ENGINE=INNODB DEFAULT CHARSET=utf8;

-- Packages_config
CREATE TABLE IF NOT EXISTS Packages_config(
    config_id  integer auto_increment not null unique,
    package VARCHAR(100) not null,
    name VARCHAR(100) not null,
    value VARCHAR(255),
    context VARCHAR(100),
    PRIMARY KEY (config_id, package),
    KEY package ( package ),
    CONSTRAINT Packages_config_ibfk_1 FOREIGN KEY (package) REFERENCES Packages (package) ON DELETE CASCADE
)ENGINE=INNODB DEFAULT CHARSET=utf8;

-- Node_Package_Status
CREATE TABLE IF NOT EXISTS Node_Package_Status(
    current  integer,
    error  text,
    node_id  integer not null,
    package  VARCHAR(100) not null,
    requested  integer not null default 1,
    curr integer,
    status integer,
    ex_status  integer not null default 0,
    selected  integer not null default 0,
    errorMsg VARCHAR(100),
    client_nodes VARCHAR(500),
    PRIMARY KEY (node_id, package, requested),
    KEY node_id ( node_id ),
    KEY package ( package ),
    KEY requested ( requested ),
    KEY curr ( curr ),
    KEY status ( status ),
    CONSTRAINT Node_Package_Status_ibfk_1 FOREIGN KEY (node_id) REFERENCES Nodes (id) ON DELETE CASCADE,
    CONSTRAINT Node_Package_Status_ibfk_2 FOREIGN KEY (package) REFERENCES Packages (package) ON DELETE CASCADE,
    CONSTRAINT Node_Package_Status_ibfk_3 FOREIGN KEY (requested) REFERENCES Status (id) ON DELETE CASCADE,
    CONSTRAINT Node_Package_Status_ibfk_4 FOREIGN KEY (curr) REFERENCES Status (id) ON DELETE CASCADE,
    CONSTRAINT Node_Package_Status_ibfk_5 FOREIGN KEY (status) REFERENCES Package_status (id) ON DELETE CASCADE
)ENGINE=INNODB DEFAULT CHARSET=utf8;

-- Group_Nodes
CREATE TABLE IF NOT EXISTS Group_Nodes(
    group_name VARCHAR(100) not null,
    node_id  integer not null,
    PRIMARY KEY (node_id, group_name),
    KEY node_id ( node_id ),
    KEY group_name ( group_name ),
    CONSTRAINT Group_Nodes_ibfk_1 FOREIGN KEY (node_id) REFERENCES Nodes (id) ON DELETE CASCADE,
    CONSTRAINT Group_Nodes_ibfk_2 FOREIGN KEY (group_name) REFERENCES Groups (name) ON DELETE CASCADE ON UPDATE CASCADE
)ENGINE=INNODB DEFAULT CHARSET=utf8;

-- Group_Packages
-- This table is used to saved information from Selector, i.e., information
-- about selected OPKGs.
CREATE TABLE IF NOT EXISTS Group_Packages(
    group_name VARCHAR(100) not null,
    package  VARCHAR(100) not null,
    selected  integer  DEFAULT '0',
    PRIMARY KEY (package, group_name),
    KEY package ( package ),
    KEY group_name ( group_name ),
    CONSTRAINT Group_Packages_ibfk_1 FOREIGN KEY (package) REFERENCES Packages (package) ON DELETE CASCADE,
    CONSTRAINT Group_Packages_ibfk_2 FOREIGN KEY (group_name) REFERENCES Groups (name) ON DELETE CASCADE ON UPDATE CASCADE
)ENGINE=INNODB DEFAULT CHARSET=utf8;

-- Image_Package_Status
CREATE TABLE IF NOT EXISTS Image_Package_Status(
    current  integer,
    error  text,
    image_id  integer not null,
    package  VARCHAR(100) not null,
    requested  integer not null default 1,
    curr integer,
    status integer,
    ex_status  integer not null default 0,
    selected  integer not null default 0,
    errorMsg VARCHAR(100),
	client_nodes VARCHAR(500),
    PRIMARY KEY (image_id, package, requested),
    KEY image_id ( image_id ),
    KEY package ( package ),
    KEY requested ( requested ),
    KEY curr ( curr ),
    KEY status ( status ),
    CONSTRAINT Image_Package_Status_ibfk_1 FOREIGN KEY (image_id) REFERENCES Images (id) ON DELETE CASCADE,
    CONSTRAINT Image_Package_Status_ibfk_2 FOREIGN KEY (package) REFERENCES Packages (package) ON DELETE CASCADE,
    CONSTRAINT Image_Package_Status_ibfk_3 FOREIGN KEY (requested) REFERENCES Status (id) ON DELETE CASCADE,
    CONSTRAINT Image_Package_Status_ibfk_4 FOREIGN KEY (curr) REFERENCES Status (id) ON DELETE CASCADE,
    CONSTRAINT Image_Package_Status_ibfk_5 FOREIGN KEY (status) REFERENCES Package_status (id) ON DELETE CASCADE
)ENGINE=INNODB DEFAULT CHARSET=utf8;

-- Wizard_status
CREATE TABLE IF NOT EXISTS Wizard_status(
    id  integer   not null unique primary key,
    step_name   CHAR(50),
    status      CHAR(10)
);

-- Manage_status
CREATE TABLE IF NOT EXISTS Manage_status(
    id  integer   not null unique primary key,
    wizard_id   integer not null,
    step_name   CHAR(50),
    status      CHAR(10)
);

-- Partitions
CREATE TABLE IF NOT EXISTS Partitions(
    partition_id      integer   auto_increment not null unique primary key,
    name              CHAR(50),
    distro            CHAR(50)
)ENGINE=INNODB DEFAULT CHARSET=utf8;

-- Cluster_Partitions
CREATE TABLE IF NOT EXISTS Cluster_Partitions(
    cluster_id      integer         not null,
    partition_id    integer         not null,
    PRIMARY KEY     ( cluster_id, partition_id ),
    KEY             cluster_id      ( cluster_id ),
    KEY             partition_id    ( partition_id ),
    CONSTRAINT      Cluster_Partitions_ibfk_1 FOREIGN KEY (cluster_id) REFERENCES Clusters (id) ON DELETE CASCADE,
    CONSTRAINT      Cluster_Partitions_ibfk_2 FOREIGN KEY (partition_id) REFERENCES Partitions (partition_id) ON DELETE CASCADE
)ENGINE=INNODB DEFAULT CHARSET=utf8;

-- Partition_Nodes
CREATE TABLE IF NOT EXISTS Partition_Nodes(
    partition_id    integer         not null,
    node_id         integer         not null,
    node_type       integer         not null,
    PRIMARY KEY     ( partition_id, node_id ),
    KEY             partition_id    ( partition_id ),
    KEY             node_id         ( node_id ),
    CONSTRAINT      Partition_Nodes_ibfk_1 FOREIGN KEY (partition_id) REFERENCES Partitions (partition_id) ON DELETE CASCADE,
    CONSTRAINT      Partition_Nodes_ibfk_2 FOREIGN KEY (node_id) REFERENCES Nodes (id) ON DELETE CASCADE
)ENGINE=INNODB DEFAULT CHARSET=utf8;

INSERT INTO Wizard_status VALUES(0,'download_packages','');
INSERT INTO Wizard_status VALUES(1,'select_packages','');
INSERT INTO Wizard_status VALUES(2,'configure_packages','');
INSERT INTO Wizard_status VALUES(3,'install_server','normal');
INSERT INTO Wizard_status VALUES(4,'build_image','disabled');
INSERT INTO Wizard_status VALUES(5,'addclients','disabled');
INSERT INTO Wizard_status VALUES(6,'netboot','disabled');
INSERT INTO Wizard_status VALUES(7,'post_install','disabled');
INSERT INTO Wizard_status VALUES(8,'test_install','disabled');

INSERT INTO Manage_status VALUES(1,5,'delete_nodes5','disabled');
INSERT INTO Manage_status VALUES(2,5,'monitor_deployment','disabled');
INSERT INTO Manage_status VALUES(3,5,'netbootmgr','disabled');
INSERT INTO Manage_status VALUES(4,5,'ganglia','disabled');
INSERT INTO Manage_status VALUES(5,8,'add_nodes','disabled');
INSERT INTO Manage_status VALUES(6,8,'delete_nodes8','disabled');
INSERT INTO Manage_status VALUES(7,8,'install_uninstall_packages','disabled');

INSERT INTO Package_status VALUES(1, 'should-be-installed_phase_done');
INSERT INTO Package_status VALUES(2, 'run-configurator_phase_done');
INSERT INTO Package_status VALUES(3, 'install-bin-pkgs_phase_done');
INSERT INTO Package_status VALUES(4, 'post-image_phase_done');
INSERT INTO Package_status VALUES(5, 'post-clients_phase_done');
INSERT INTO Package_status VALUES(6, 'post-install_phase_done');
INSERT INTO Package_status VALUES(7, 'installed');
INSERT INTO Package_status VALUES(8, 'error');
