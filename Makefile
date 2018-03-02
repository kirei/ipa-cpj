install:
	install -m 544 cpj.sh /usr/local/bin/cpj
	install -m 444 systemd/cpj.path /lib/systemd/system/cpj.path
	install -m 444 systemd/cpj.service /lib/systemd/system/cpj.service
