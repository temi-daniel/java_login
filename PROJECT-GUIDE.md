# Java Login App: Project Kit

Everything you need to deploy the Java login app on AWS with your own infrastructure code (Terraform or anything else). The original project's Terraform is not included.

## What's in this kit

```
Java-Login-App/        Spring Boot 2.7 app (packaged as a WAR, Java 11, JSP pages, MySQL)
db/schema.sql          Creates the UserDB database, Employee table and a least-privilege app user
deploy/
  install-tomcat.sh    Installs Java 11 + Tomcat 9 and deploys the WAR (also usable as EC2 user data)
  tomcat.service       systemd unit for Tomcat
  tomcat.env.example   DB settings file template (copy to /etc/tomcat.env on the server)
PROJECT-GUIDE.md       This file
```

Changes I made to the original app:
- `application.properties` now reads `DB_URL`, `DB_USERNAME` and `DB_PASSWORD` from environment variables instead of the original author's hardcoded RDS endpoint and `Admin123` password.
- `settings.xml` was **removed**. It contained someone else's real JFrog login. Don't use it. Maven Central works with no settings file.
- The Java code and JSP pages are untouched.

## How the app works

| URL | What it does |
|---|---|
| `/` or `/home` | Home page |
| `/register` | Register form, inserts a row into `Employee` |
| `/login` | Login form, looks the user up in `Employee` |

The app talks to MySQL directly with JDBC. It needs a database called `UserDB` with a table called `Employee` (see `db/schema.sql`). Tomcat serves it on port **8080**.

## Step 1: Build the WAR (on your machine or a CI server)

You need **JDK 11** and **Maven 3.8+**.

```bash
cd Java-Login-App
mvn clean package -DskipTests
# output: target/dptweb-1.0.war
```

- Use `mvn`, not `./mvnw`. The Maven wrapper in the original repo is broken (its `.mvn` folder is missing).
- `-DskipTests` is needed because the included test tries to start the app against a real database.

## Step 2: Create the database

On your RDS MySQL instance (in a private subnet, reachable only from the app security group):

```bash
mysql -h <rds-endpoint> -u admin -p < db/schema.sql
```

Edit the `appuser` password in `schema.sql` first. The app only needs SELECT and INSERT.

## Step 3: Deploy to a server

On an EC2 instance (Amazon Linux 2023 or Ubuntu):

```bash
sudo ./deploy/install-tomcat.sh /path/to/dptweb-1.0.war
sudo nano /etc/tomcat.env        # put in your real RDS endpoint, user and password
sudo systemctl restart tomcat
```

Check it: `curl -i http://localhost:8080/` should return 200, and `http://<server>:8080/login` should show the login form.
Logs: `/opt/tomcat/logs/catalina.out`.

For an Auto Scaling Group, upload the WAR to S3, give the instance profile read access to it, and have the launch template's user data download the WAR and run `install-tomcat.sh`. Read the DB password from SSM Parameter Store or Secrets Manager instead of baking it into the AMI or user data.

## What your own Terraform needs to create

A simple, sensible 3-tier layout:

| Piece | Notes |
|---|---|
| VPC, 2 public + 2 private subnets (2 AZs) | Internet gateway for public; NAT gateway for private egress |
| Application Load Balancer (public subnets) | Listener 80 (and 443 with ACM cert), target group port **8080**, health check path `/`, expect 200 |
| Launch template + Auto Scaling Group (private subnets) | Instances run Tomcat + the WAR, attached to the ALB target group |
| RDS MySQL (private subnets, subnet group) | Multi-AZ optional for a lab; not publicly accessible |
| Security groups | ALB: 80/443 from internet. App: 8080 from ALB SG only. RDS: 3306 from app SG only |
| IAM instance profile | S3 read for the WAR, SSM/Secrets read for DB password, CloudWatch agent |
| CloudWatch | Log group for `catalina.out`, alarms on CPU and unhealthy hosts |

If you want the original project's extra tiers (Nginx front tier, CloudFront, ElastiCache, a second VPC with Transit Gateway), the app doesn't need any of them to run. They're architecture practice. Note that the original README's SQL example (`javaapp` database, `users` table) does **not** match the code; use `db/schema.sql` here.

## Known problems to be aware of

1. **Possible redirect/403 on `/login`.** `spring-boot-starter-security` is in `pom.xml` but nothing in the code uses it. With no security config, Spring Security can protect every URL by default and block form posts. I could not build or run the app in my workspace (no Maven Central access), so I haven't confirmed this. If you see a redirect loop, 403 errors or a generated-password prompt, delete that one `<dependency>` block from `pom.xml` and rebuild.
2. **Login state is shared between users.** In `login.java` the `userId` and `errorMessage` fields are on a singleton controller and never reset. After one successful login, later failed logins can still show the logged-in page. Make them local variables inside the `login()` method.
3. **SQL injection.** Both `login.java` and `register.java` build SQL by joining in user input. Use `PreparedStatement` with `?` placeholders.
4. **Plain-text passwords.** Passwords are stored and compared as-is. Hash them (for example with bcrypt) before this holds real data.
5. **Hardcoded driver class.** `com.mysql.jdbc.Driver` is the old name. It still works with the bundled connector but logs a deprecation warning.

Items 2 to 4 are fine to leave for a DevOps practice project, but fixing them makes a good talking point for your write-up.

## Optional CI/CD ideas for your project

- GitHub Actions or Jenkins: checkout, `mvn clean package`, upload the WAR to S3, trigger an ASG instance refresh.
- SonarCloud for code quality: add `sonar.projectKey`, `sonar.organization` and `sonar.host.url` to `pom.xml` properties and run `mvn sonar:sonar` with your own token.
- Artifact storage: S3 is enough. JFrog is optional, and you'd create your own account and put credentials in environment variables, never in a committed `settings.xml`.
