# Introduction

To ensure this evaluation goes smoothly, please respect the following set of rules:

- Please remain courteous, polite, respectful and constructive at all times during this exchange. The trust bond between the school's community and yourself depends on it.
- Should you notice any malfunctions within the submitted project, make sure you take the time to discuss those with the student (or group of students) being graded.
- Keep in mind that some subjects can be interpreted differently. If you come across a situation where the student you're grading has interpreted the subject differently than you, try and judge fairly whether their interpretation is acceptable or not, and grade them accordingly. Our peer-evaluation system can only work if you both take it seriously.

---

# Guidelines

- You may only evaluate whatever is in the **GiT submission directory** of the student you are grading.
- Make sure to check whether the GiT submission directory belongs to the student (or group) you're grading, and that it's the right project.
- Make sure no mischievous aliases have been used to trick you into correcting something that is not actually in the official submitted directory.
- Any script created to make this evaluation session easier - whether it was produced by you or the student being graded - must be checked rigorously in order to avoid bad surprises.
- If the student who is grading this project hasn't done the project him/herself yet, he/she must read the whole topic before starting the evaluation session.
- Use the flags available to you on this scale in order to report a submission directory that is empty, non-functional, that contains a norm errors or a case of cheating, etc... In this case, the evaluation session ends and the final grade is `0` (or `-42`, in case of cheating). However, unless the student has cheated, we advise you to go through the project together in order for the two (or more) of you to identify the problems that may have led for this project to fail, and avoid repeating those mistakes for future projects.

---

Attachments : [subject.pdf](./subject.swifty-companion.pdf)

---

# Preliminaries

## Preliminary instructions

First check the following items:

- There is something in the git repository
- No cheating, student must be able to explain the code.
- Any credentials, API keys, environment variables must be set inside a `.env` file during the evaluation. In case any credentials, API keys are available in the git repository and outside of the `.env` file created during the evaluation, the evaluation stop and the mark is `0`.

If an item in this list is not respected, the notation stops.  
Use the appropriate flag. You are encouraged to continue the discussion but the scale ends now.

[ ] Yes  
[ ] No  

<br>

# First section

## Mandatory

### Compilation

Check that the project compiles and launches the simulator correctly. If this is not the case, correction stops.

[ ] Yes  
[ ] No  

### Views

Check that at least **2 views** are displayed:

- The first view must contain a text input field to search for 42 logins.
- The second view must display the user information, if the login exists.

[ ] Yes  
[ ] No  

### API

Check that the most recent **42 API** is used.

[ ] Yes  
[ ] No  

### Search User

Check with several logins that everything works:

- With a login student or staff of your campus.
- With a login that does not exist.

[ ] Yes  
[ ] No  

### Dashboard -> Profile View

Check that the users' details are displayed correctly. At least four details should be shown, such as `login`, `email`, `mobile`, `level`, `location`, `wallet`, `evaluations` etc., along with the picture.

[ ] Yes  
[ ] No  

### Dashboard -> Skills

Ensure the skills are displayed along with their levels and percentages.

[ ] Yes  
[ ] No  

### Dashboard -> Projects

Ensure that all projects completed by the user are displayed, including the ones that have failed.

[ ] Yes  
[ ] No  

### Autolayout

Verify that the application is compatible and runs smoothly on multiple phones with different screens size, ensuring that the layout adapts correctly to each screen size.

[ ] Yes  
[ ] No  

### Token API

Verify that the application does not create a new token for each request.

[ ] Yes  
[ ] No  

<br>

# Bonus

## Use of Oauth2

The token has an expiration date. If the token expires, the application should be able to refresh it.

[ ] Yes  
[ ] No  
