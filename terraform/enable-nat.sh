terraform destroy \
  -target=aws_route.private_internet_route \
  -target=aws_nat_gateway.nat_gw \
  -target=aws_eip.nat_eip \
  -auto-approve