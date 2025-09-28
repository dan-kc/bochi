resource "aws_vpc" "habit_market" {
  cidr_block = "10.1.0.0/16"
  
  tags = {
    Name = "habit-market-vpc"
  }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.habit_market.id
  cidr_block        = "10.1.1.0/24"
  availability_zone = "eu-west-2a"
  
  tags = {
    Name = "habit-market-private-subnet"
  }
}

resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.habit_market.id
  cidr_block        = "10.1.2.0/24"
  availability_zone = "eu-west-2a"
}

# Additional private subnet for RDS subnet group (required minimum 2 subnets)
resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.habit_market.id
  cidr_block        = "10.1.3.0/24"
  availability_zone = "eu-west-2b"
  
  tags = {
    Name = "habit-market-private-subnet-b"
  }
}
