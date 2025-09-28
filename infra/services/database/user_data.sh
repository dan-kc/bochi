#!/bin/bash
set -e

# Join ECS Cluster
echo ECS_CLUSTER=${cluster_name} >> /etc/ecs/ecs.config

# Install AWS CLI
yum install -y aws-cli

# Get instance metadata
INSTANCE_ID=$(ec2-metadata --instance-id | cut -d " " -f 2)
AVAILABILITY_ZONE=$(ec2-metadata --availability-zone | cut -d " " -f 2)
REGION=$(echo $AVAILABILITY_ZONE | sed 's/[a-z]$//')

# Wait for volume to be available
sleep 30

# Attach EBS volume if not already attached
VOLUME_STATE=$(aws ec2 describe-volumes --volume-ids ${volume_id} --region $REGION --query 'Volumes[0].State' --output text)
if [ "$VOLUME_STATE" == "available" ]; then
    aws ec2 attach-volume --volume-id ${volume_id} --instance-id $INSTANCE_ID --device /dev/sdf --region $REGION
    
    # Wait for volume to attach
    while [ ! -e /dev/sdf ] && [ ! -e /dev/xvdf ]; do
        echo "Waiting for volume to attach..."
        sleep 5
    done
fi

# Determine the device name (could be /dev/sdf or /dev/xvdf)
if [ -e /dev/sdf ]; then
    DEVICE=/dev/sdf
else
    DEVICE=/dev/xvdf
fi

# Check if volume needs formatting
if ! file -s $DEVICE | grep -q "ext4"; then
    echo "Formatting new volume..."
    mkfs -t ext4 $DEVICE
fi

# Create mount point
mkdir -p /mnt/postgres-data

# Mount the volume
mount $DEVICE /mnt/postgres-data

# Add to fstab for persistent mounting
UUID=$(blkid -s UUID -o value $DEVICE)
echo "UUID=$UUID /mnt/postgres-data ext4 defaults,nofail 0 2" >> /etc/fstab

# Set permissions
chmod 755 /mnt/postgres-data

# Create postgres data directory with correct permissions
mkdir -p /mnt/postgres-data/pgdata
chown -R 999:999 /mnt/postgres-data  # 999 is the postgres user in the container

echo "EBS volume mounted successfully"
