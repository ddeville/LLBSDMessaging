## LLBSDMessaging

### Interprocess communication via Berkeley sockets on iOS

- Mach ports are technically available on iOS but the mach bootstrap server is not available so we cannot register custom ports
- Also, even if we could, XPC and `NSMachPort` are not available so it could be quite painful
- Since iOS 8, applications from the same group can share a directory on the file system
- iOS is built on top of Unix
- In Unix, everything is a file!
- We can use Berkeley sockets (a file) to communicate between processes
- This solves the channel problem but we still need to figure out a few more things
- We need the process to find and connect to each other
- We need a mechanism to write and read from the socket in a non-blocking fashion
- We need a "protocol" to frame our messages on the wire
- The client and server need to agree on the format
- We need to handle errors and invalidations
- We need to support sending complex data, including application-specific data
- The connection shouldn’t be aware of the format of the data itself but it should ensure that it is encoded and decoded in a secure manner on each end
