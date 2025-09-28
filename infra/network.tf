resource "aws_vpc" "habit_market" {
  cidr_block = "10.1.0.0/16"
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.habit_market.id
  cidr_block        = "10.1.1.0/24"
  availability_zone = "eu-west-2a"
}

resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.habit_market.id
  cidr_block        = "10.1.2.0/24"
  availability_zone = "eu-west-2a"
}
