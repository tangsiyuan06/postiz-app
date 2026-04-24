import { IsNotEmpty, IsString } from 'class-validator';

export class SsoLoginDto {
  @IsNotEmpty()
  @IsString()
  auth_code: string;
}
