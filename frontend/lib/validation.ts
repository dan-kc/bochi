export type ValidationError =
  | "InvalidEmailAddress"
  | "EmailTooLong"
  | "PasswordNotAscii"
  | "PasswordTooLong"
  | "PasswordTooShort";

const EMAIL_REGEX = /^[\w\.-]+@[a-zA-Z\d\.-]+\.[a-zA-Z]{2,}$/;

export function validateEmail(email: string): ValidationError[] {
  const errors: ValidationError[] = [];

  if (!EMAIL_REGEX.test(email)) {
    errors.push("InvalidEmailAddress");
  }
  if (email.length > 254) {
    errors.push("EmailTooLong");
  }

  return errors;
}

export function validatePassword(password: string): ValidationError[] {
  const errors: ValidationError[] = [];

  // Check if password contains only ASCII characters
  if (!/^[\x00-\x7F]*$/.test(password)) {
    errors.push("PasswordNotAscii");
  }
  if (password.length > 64) {
    errors.push("PasswordTooLong");
  }
  if (password.length < 8) {
    errors.push("PasswordTooShort");
  }

  return errors;
}

export function validateAuthInput(
  email: string,
  password: string,
): ValidationError[] {
  return [...validateEmail(email), ...validatePassword(password)];
}

export function getErrorMessage(error: ValidationError): string {
  switch (error) {
    case "InvalidEmailAddress":
      return "Please enter a valid email address";
    case "EmailTooLong":
      return "Email address is too long (max 254 characters)";
    case "PasswordNotAscii":
      return "Password must contain only ASCII characters";
    case "PasswordTooLong":
      return "Password is too long (max 64 characters)";
    case "PasswordTooShort":
      return "Password must be at least 8 characters";
    default:
      return "An error occurred";
  }
}
