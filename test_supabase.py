from app.core.supabase import supabase

def main():
    resp = supabase.table("programs").select("*").limit(1).execute()
    print("Got data:", resp.data)

if __name__ == "__main__":
    main()
