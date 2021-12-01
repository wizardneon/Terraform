*********************************************

Вам нужно проверить , соответствуют ли переменные тому что вы хотите получить в итоге. Вам нужно передать  credentials для доступа к aws тераформу. Если вы не знаете как тераформ получает их обратитесь к официальной документации. 
  To plan:   
  terraform plan -var-file="user.tfvars"

  To apply:    
  terraform apply -var-file="user.tfvars"

  To destroy:    
  terraform destroy -var-file="user.tfvars"

  *********************************
