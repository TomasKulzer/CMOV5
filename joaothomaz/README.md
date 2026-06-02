
To setup the scripts in the PC one should firstly:
Notes: 
  - All these instructions assume `oai`,`oai-cn5g` and `flexric` folders are present at the ~/ directory.
  - Is recommended to have 5 terminals connected to the **gNB** machine:
    - Terminal 1: Main script
    - Terminal 2: UE1 (or single UE case)
    - Terminal 3: UE2
    - Terminal 4: gNB
    - Terminal 4: iperf (for monitoring)
  - Whenever a output which states to do 'tmux attach -t <gnb|ue|ue1|ue2|iperf>' pops up, the user should do it in on of the mentioned terminals. It guarantees that flow occurs correctly.
  - If it takes too long the script may break. This can be changed in the file adjusting the `sleep` timers, increasing them. Also be ready to insert the sudo password: **mobile**.
  - Make sure `tmux` and `iperf` is installed
  - I believe every capture in the `plots-task34` and `wiresharkcaptures-task12` folders are valid, and can be inserted in the report.

- Connect to the **10.227.20.82** (in the script is assumed as the **Core**) and to the **10.227.20.72** (in the script is assumed as the **gNB**).
  - If connected to different IPs, one can simply change the respective variables in the scripts
- Run `bash initial_setup.sh core` in the **Core** host. This will bring the dockers from the **Core** up, while also deploying the Firewall rules. After running the script this machine is active.
- Run `bash initial_setup.sh gnb` in the **gNB** host. This will turn the **gNB**, while also deploying the Firewall rules. Upon this configuration this host will ping the **Core**'s `ext-dn` and `amf` to check if everything is fine.
- To initiate the tasks one can simply do `bash running_steps.sh core <1|2|3>` in the **Core** host. This will initiate a `tcpdump` command that will capture packets coming to this machine. It's not mandatory, but useful since the results from the communication will be exported to a `.pcap` file in /tmp/ directory, and it can be used in the final report.
- To initiate the tasks one can simply do `bash running_steps.sh gnb <1|2|3|4|5> <20|100>` in the **gNB** host.
  - For task 1 both a Uplink ping will occur from the User Equipment to the External Data Network, and vice-versa for the Downlink ping case;
  - For task 2 both a Uplink ping will occur from the User Equipment 1 and 2 to the External Data Network, and vice-versa for the Downlink ping case. The `multi_ue.sh` script should be place at the ~/ directory of the **gNB** machine.
  - For task 3, the third argument (20MHz or 100MHz) will define which parameters will be placed in the `.conf` file, to comply with the https://www.sqimway.com/nr_refA.php. **At the moment 20MHz can't be reproduced.**
  - For task 4, the third argument will still be used, and will define the settings for **UEs**. ICMPs pings to determine RTT for both UEs will happen (Uplink and Downlink cases, similar to Task 2) and then using the `iperf` command (Uplink and Downlink cases) we will determine the throughput of both devices, in a TCP vs UDP situation.
    - The `.txt` and `.csv` files exported to ~/ can then be processed by the `plots-task34/plotter.py` Python script that will plot the graphics necessary to insert in the report. 
  - For task 5, the web monitoring interface needs only `server.py` to be run with:
```bash
	python3 server.py # running on port 8888  
``` 
  
- At the moment `x2go` is not allowing the web browser to open therefore the way to access the Web 
UI is by port-forwarding through ssh on to the client/user machine with:

```bash
	ssh -fNL 8888:localhost:8888 <remote_hostname>@<remote_host_IP>
```

- After that just open a browser and type the url: `http://localhost:8888/index.html` and the UI comes
up.
