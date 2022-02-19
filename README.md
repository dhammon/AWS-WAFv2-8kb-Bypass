# AWS WAFv2 8kb Bypass
## Backgroud
[AWS Documents](https://docs.aws.amazon.com/waf/latest/developerguide/web-request-body-inspection.html) explains that only the first 8kb in body requests are inspected while passing the entire request.  The document further suggests that administrators block requests with body's greater than 8kb.  AWS's [Core rule set](https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-baseline.html#aws-managed-rule-groups-baseline-crs) has a rule that blocks body requests greater than 8kb; however, not all users of the AWS WAFv2 service subscribe the the CRS managed ruleset or have created 8kb blocking rules.

## Test Environment
The main.tf is a Terrform file that creates a basic AWS environment with a VPC, Routes, Security Groups, Application Load Balancer, WAF with one XSS rule, and a vulnerable EC2 Apache2/PHP web server running on Ubuntu.

Standing up the environment:
```
aws configure
terraform init
terraform apply
```

Users will need an AWS account configured.  The EC2 instance is configured with an elastic IP address and SSH open to the internet for ease of access if needed.  Make sure to update the main.tf file with a valid SSH key name associated with your AWS account.  The load balancer's URL and web server's public IP are displayed after Terraform successfully builds the environment.

The WAF rule is applied only to the body of requests and the web server's index.php page echo's the value of the 'cmd' GET/POST parameter without input validation or secure rendering.

## Bypass Demonstration
Once the environment is built the load_balancer_dns is displayed.  With Burp intercept running, navigate to the URL and capture the request.  Move the request to Burp's repeater and change the request method to POST.  Add the 'cmd' POST parameter and 'Hello World!' value to demonstrates the rendering of input and the potential XSS vulnerability:
![Hello World](/images/helloWorld.jpg)

Changing the cmd parameter value to an XSS payload *<script>alert(1)</script>* demonstrates the WAF rule blocks the request:
![XSS Blocked](/images/xssBlocked.jpg)

Adding a dummy parameter with any value greater than 8kb before the cmd paramter bypasses the WAF rule:
![Rule Bypassed](/images/ruleBypassed.jpg)


