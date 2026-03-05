1. Launch an trn2.3xlarge instance with neuron deep learning ami 
   - Public access
   - Security Group: 3003/TCP
   - EBS volume:200G
3. Download docker image and model files
   ```
   chmod +x setup.sh
   ./setup.sh
   ```
4. Start docker container
   ```
   chmod +x run.sh
   ./run.sh
   ```
5. Install xcode and compile mac client
6. Enjoy!
