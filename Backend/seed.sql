-- Seed initial admin user
INSERT INTO "Users" ("Name", "Password") 
VALUES ('admin', 'skals')
ON CONFLICT DO NOTHING;


