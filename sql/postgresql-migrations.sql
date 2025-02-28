-- Initial schema creation for the PostgreSQL database
-- This file can be used to initialize the Aurora PostgreSQL database

-- Create a sample schema
CREATE SCHEMA IF NOT EXISTS app;

-- Create users table
CREATE TABLE IF NOT EXISTS app.users (
    user_id SERIAL PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    email VARCHAR(100) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create products table
CREATE TABLE IF NOT EXISTS app.products (
    product_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    price DECIMAL(10, 2) NOT NULL,
    stock_quantity INTEGER NOT NULL DEFAULT 0,
    is_available BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create orders table
CREATE TABLE IF NOT EXISTS app.orders (
    order_id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES app.users(user_id),
    order_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    order_status VARCHAR(20) NOT NULL DEFAULT 'pending',
    total_amount DECIMAL(10, 2) NOT NULL,
    shipping_address TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create order_items table
CREATE TABLE IF NOT EXISTS app.order_items (
    order_item_id SERIAL PRIMARY KEY,
    order_id INTEGER NOT NULL REFERENCES app.orders(order_id),
    product_id INTEGER NOT NULL REFERENCES app.products(product_id),
    quantity INTEGER NOT NULL,
    price_per_unit DECIMAL(10, 2) NOT NULL,
    total_price DECIMAL(10, 2) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create function to update timestamp
CREATE OR REPLACE FUNCTION app.update_modified_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create triggers for updated_at timestamps
CREATE TRIGGER update_users_modtime
BEFORE UPDATE ON app.users
FOR EACH ROW EXECUTE FUNCTION app.update_modified_column();

CREATE TRIGGER update_products_modtime
BEFORE UPDATE ON app.products
FOR EACH ROW EXECUTE FUNCTION app.update_modified_column();

CREATE TRIGGER update_orders_modtime
BEFORE UPDATE ON app.orders
FOR EACH ROW EXECUTE FUNCTION app.update_modified_column();

-- Create index for common queries
CREATE INDEX idx_user_username ON app.users(username);
CREATE INDEX idx_product_name ON app.products(name);
CREATE INDEX idx_order_user ON app.orders(user_id);
CREATE INDEX idx_order_status ON app.orders(order_status);
CREATE INDEX idx_order_item_order ON app.order_items(order_id);
CREATE INDEX idx_order_item_product ON app.order_items(product_id);

-- Create a view for order summaries
CREATE OR REPLACE VIEW app.order_summary AS
SELECT 
    o.order_id,
    o.order_date,
    o.order_status,
    o.total_amount,
    u.username,
    u.email,
    COUNT(oi.order_item_id) AS item_count
FROM 
    app.orders o
JOIN 
    app.users u ON o.user_id = u.user_id
JOIN 
    app.order_items oi ON o.order_id = oi.order_id
GROUP BY 
    o.order_id, u.username, u.email;

-- Insert sample data
INSERT INTO app.users (username, email, password_hash, first_name, last_name)
VALUES
    ('johndoe', 'john.doe@example.com', 'hashed_password_here', 'John', 'Doe'),
    ('janedoe', 'jane.doe@example.com', 'hashed_password_here', 'Jane', 'Doe')
ON CONFLICT (username) DO NOTHING;

INSERT INTO app.products (name, description, price, stock_quantity)
VALUES
    ('Laptop', 'High-performance laptop', 1299.99, 50),
    ('Smartphone', 'Latest model smartphone', 699.99, 100),
    ('Wireless Headphones', 'Noise-canceling headphones', 199.99, 200)
ON CONFLICT DO NOTHING;

-- Comment for deployment use:
-- This script can be applied to the Aurora PostgreSQL database using the following command:
-- psql -h <aurora-endpoint> -U <master_username> -d appdb -f initdb.sql
