# snarf 
 
This script reads a domain and calls docker run elceef/dnstwist on the domain. It then pipes the results into a file, after which it reads the file and use cutycapt to create a picture folder with screenshots of the websites it found.

Requires: Fully functional docker and cutycapt (which also requires X)
Optional: If you are running on a headless server, make sure to install xvfb because cutycapt won't run without at least a dummy X.

Thanks!

TitaniumCoder477

Latest download: https://github.com/TitaniumCoder477/snarf/blob/master/snarf/bin/Release/snarf.sh
