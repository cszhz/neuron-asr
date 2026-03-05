1. Launch a trn2.3xlarge instance
   - Ubuntu 24.04 Neuron Deep Learning AMI 
   - Public access
   - Security Group: 3003/TCP
   - EBS volume:200G
2. Server
   
2.1 SSH to Trn2 instance

2.2 Download docker image and model files
   ```
   chmod +x setup.sh
   ./setup.sh
   ```

2.3 Start docker container
   ```
   chmod +x run.sh
   ./run.sh
   ```

3. Mac Client

Install xcode and compile mac client

4. Enjoy!
