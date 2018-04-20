# snaplogic-it

- Banner-Parlance current version v1.0.1
    - REST GET endpoint: https://appconnect.vassar.edu/api/vassarapi/v1/employee
    - Oracle SP= DAIES.get_employee_dataset
    - output= 1 txt file sftp to Parlance server.
    - task= (pipeline, sftp) scheduled Daily at 6PM
    - vendor support={}
    - v1.0.1

- Google-AD
    - Captures Google Worksheet data (802.1x keyboardless devices) and uses AD Create Entry snap to create account
    - output= no output, change to AD
    - task= scheduled pipeline running hourly
    - v1.0.0

- Google-AD.Password - [] [] [] []
    - Captures Google Worksheet data (802.1x keyboardless devices) and uses AD Update Entry snap to update password for each CN
    - output= no output, change to AD
    - task= NA (child pipeline of Google.AD)
    - v1.0.0
